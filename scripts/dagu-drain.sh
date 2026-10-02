#!/usr/bin/env bash
# Drain Dagu, then recreate or update it (docker#68). Jenkins' "Prepare for Shutdown":
#   1. pull the image (unless --no-pull). --update with nothing newer: done, nothing touched.
#   2. pause the scheduler (Dagu's global pause, dagucloud/dagu#2762): no new scheduled
#      runs; running ones finish; manual Start still works. The pause survives a restart.
#   3. wait until no run is in flight (a .proc file per live run under dagu/data/proc).
#      Past --max-wait: lift the pause, recreate nothing, alert.
#   4. tag the running image updates-rollback/dagu:dagu, `docker compose up -d --force-recreate`.
#   5. verify: /api/v1/health answers, lift the pause, the next deploy-reconciler run
#      (its first step is `ssh dockerhost`) goes green. A new image that fails is rolled
#      back to the tagged one and verified again; if that fails too, Dagu stays paused.
#   6. stamp the applied config (dagu-applied.sha256, read by ./deploy), list the
#      scheduled runs the pause skipped (no DAG here has catch-up, so they never replay),
#      post to #dagu as Rabbot; @brandon only when something failed.
#
# Never run it inside a Dagu step and wait: the recreate kills that step. Launch it detached:
#   systemd-run --user --unit=dagu-drain --collect ~/projects/docker/scripts/dagu-drain.sh --update
# ./deploy (config changes on merge) and dagu/dags/container-updates.yaml (weekly) do exactly that.
#
#   dagu-drain.sh --recreate | --update [--no-pull] [--max-wait 6h] [--dry-run]
#
# Needs dagu/.drain.env (gitignored, chmod 600): DAGU_API_TOKEN=<admin API token>, or
# DAGU_USER + DAGU_PASS for basic auth. Agents never read it.
set -uo pipefail

ROOT="${DRAIN_ROOT:-/home/brandon/projects/docker}"
DIR="$ROOT/dagu"
API="${DRAIN_API:-http://localhost:8014/api/v1}"
ENVF="$DIR/.drain.env"
STAMP="$ROOT/logs/deploy/dagu-applied.sha256"
OUT="$ROOT/logs/dagu-drain"
SAY="${DRAIN_SAY:-/home/brandon/projects/agent-bus/bin/say}"
CHANNEL="${DRAIN_CHANNEL:-#dagu}"
ROLLBACK=updates-rollback/dagu:dagu
CONFIG_FILES=(docker-compose.yml config.yaml ssh_include)

mode=""; pull=1; dry=0; max_wait=6h
while [ $# -gt 0 ]; do
    case "$1" in
    --recreate) mode=recreate ;;
    --update) mode=update ;;
    --no-pull) pull=0 ;;
    --max-wait) max_wait="$2"; shift ;;
    --dry-run) dry=1 ;;
    *) echo "usage: $0 --recreate | --update [--no-pull] [--max-wait 6h] [--dry-run]" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$mode" ] || { echo "say --recreate or --update" >&2; exit 2; }
case "$max_wait" in
*h) max_s=$(( ${max_wait%h} * 3600 )) ;;
*m) max_s=$(( ${max_wait%m} * 60 )) ;;
*[0-9]) max_s=$max_wait ;;
*) echo "--max-wait: 6h, 90m or seconds" >&2; exit 2 ;;
esac

mkdir -p "$OUT" "$(dirname "$STAMP")"
log_file="$OUT/$(date +%Y%m%d-%H%M%S).log"
ls -t "$OUT"/*.log 2>/dev/null | tail -n +21 | xargs -r rm -f --   # keep 20
exec > >(tee -a "$log_file") 2>&1
log() { echo "$(date '+%F %T') $*"; }
post() {   # post <ok|failed> <message>
    local who=""; [ "$1" = failed ] && who="@brandon "
    [ "$dry" = 1 ] && { log "[dry-run] would post: $2"; return; }
    printf '%s%s\nLog: `%s`\n' "$who" "$2" "$log_file" | "$SAY" rabbot "$CHANNEL" - >/dev/null || log "post failed"
}
alerted=0; pause_held=0
die() { log "FAILED: $1"; post failed "**Dagu drain** ($mode) failed: $1"; alerted=1; exit 1; }
on_exit() {   # killed (systemctl stop, OOM, reboot) while holding the pause: say so
    [ "$pause_held" = 1 ] && [ "$alerted" = 0 ] && post failed "**Dagu drain** ($mode) died mid-drain. Dagu is PAUSED: lift it on :8014 (System Status) or rerun the drain."
    sleep 1   # let tee flush
}
trap on_exit EXIT
trap 'exit 143' TERM INT

# ---- API ---------------------------------------------------------------------------
[ -r "$ENVF" ] || die "no $ENVF (see dagu/README.md, 'Recreating or updating Dagu')"
# shellcheck disable=SC1090
. "$ENVF"
auth=()
if [ -n "${DAGU_API_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer $DAGU_API_TOKEN")
elif [ -n "${DAGU_USER:-}" ]; then auth=(-u "$DAGU_USER:${DAGU_PASS:-}")
else die "$ENVF sets neither DAGU_API_TOKEN nor DAGU_USER"; fi

health() { curl -s -m 5 "$API/health" | jq -r 'select(.status=="healthy") | .version' 2>/dev/null; }
paused() { curl -s -m 10 "${auth[@]}" "$API/services/scheduler/pause" | jq -r '.paused' 2>/dev/null; }
set_pause() {   # set_pause true|false: 0 when Dagu reports the state back
    [ "$dry" = 1 ] && { log "[dry-run] would set paused=$1"; return 0; }
    curl -s -m 10 -o /dev/null -X POST "${auth[@]}" -H 'Content-Type: application/json' \
        -d "{\"paused\": $1, \"reason\": \"dagu-drain.sh --$mode (docker#68)\"}" "$API/services/scheduler/pause"
    [ "$(paused)" = "$1" ] || return 1
    [ "$1" = true ] && pause_held=1 || pause_held=0
}

# ---- image -------------------------------------------------------------------------
compose() { (cd "$DIR" && docker compose "$@"); }
image_ref=$(compose config --images 2>/dev/null | head -1)
[ -n "$image_ref" ] || die "\`docker compose config\` in $DIR gave no image"
running_id() { docker inspect dagu --format '{{.Image}}' 2>/dev/null; }
tag_id() { docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null; }

old_ver=$(health); [ -n "$old_ver" ] || die "Dagu isn't healthy before we start; not draining a broken Dagu"
[ "$(paused)" = false ] || die "can't read the pause state (bad credentials?) or Dagu is already paused; leaving it as is"
old_id=$(running_id)
log "dagu $old_ver ($old_id), $image_ref, mode $mode"

if [ "$pull" = 1 ]; then
    if [ "$dry" = 1 ]; then log "[dry-run] would pull $image_ref"
    else compose pull -q dagu || die "docker compose pull failed"; fi
fi
new_image=0; [ "$(tag_id)" != "$old_id" ] && new_image=1
if [ "$mode" = update ] && [ "$new_image" = 0 ]; then
    log "dagu $old_ver is current; nothing to do"; exit 0
fi
log "new image: $([ $new_image = 1 ] && tag_id || echo no)"

# ---- drain -------------------------------------------------------------------------
set_pause true || die "pause didn't take; recreated nothing"
paused_at=$(date -Iseconds)
cp "$DIR/data/scheduler/state.json" "$OUT/.state-at-pause.json" 2>/dev/null
log "scheduler paused"
unpause_or_die() { set_pause false || die "$1, and lifting the pause failed: Dagu is still PAUSED"; }

running() { find "$DIR/data/proc" -name '*.proc' -printf '%h\n' 2>/dev/null | sed "s#^$DIR/data/proc/##; s#/.*##" | sort -u; }
start=$(date +%s); last_note=0
while :; do
    busy=$(running | paste -sd' ')
    [ -z "$busy" ] && break
    now=$(date +%s)
    if [ $((now - start)) -ge "$max_s" ]; then
        unpause_or_die "still running after $max_wait: $busy"
        die "gave up after $max_wait waiting on: $busy. Pause lifted, nothing recreated"
    fi
    if [ $((now - last_note)) -ge 300 ]; then log "waiting on: $busy"; last_note=$now; fi
    [ "$dry" = 1 ] && { log "[dry-run] would keep waiting on: $busy"; break; }
    sleep 15
done
log "idle after $(( $(date +%s) - start ))s"

# ---- recreate + verify -------------------------------------------------------------
recreate() {
    [ "$dry" = 1 ] && { log "[dry-run] would recreate dagu"; return 0; }
    compose up -d --force-recreate dagu
}
reconciler_green() {   # a deploy-reconciler run that started after $1 finished with status 4 (success)
    local since=$1 deadline=$(( $(date +%s) + 420 )) f st
    while [ "$(date +%s)" -lt "$deadline" ]; do
        f=$(find "$DIR/data/dag-runs/deploy-reconciler" -name status.jsonl -newermt "$since" 2>/dev/null | xargs -r ls -t | head -1)
        if [ -n "$f" ]; then
            st=$(tail -1 "$f" | jq -r '.status')
            [ "$st" = 4 ] && return 0
            [ "$st" = 2 ] && return 1
        fi
        sleep 15
    done
    return 1
}
verify() {   # health within 2 min, lift the pause, then a green reconciler run
    local i v t
    [ "$dry" = 1 ] && { log "[dry-run] would verify"; return 0; }
    for i in $(seq 24); do v=$(health); [ -n "$v" ] && break; sleep 5; done
    [ -n "$v" ] || { log "health never came back"; return 1; }
    new_ver=$v
    t=$(date '+%F %T')
    set_pause false || { log "couldn't lift the pause"; return 1; }
    log "dagu $new_ver healthy, pause lifted; waiting for a deploy-reconciler run"
    reconciler_green "$t" && return 0
    set_pause true && log "deploy-reconciler didn't go green; paused again" \
        || log "deploy-reconciler didn't go green, and re-pausing failed: Dagu is UNPAUSED"
    return 1
}

# Hash the config this recreate applies now: a merge landing after the unpause must not be
# stamped as applied (./deploy would skip it).
applied=$(cd "$DIR" && sha256sum "${CONFIG_FILES[@]}")
if [ "$new_image" = 1 ] && [ "$dry" = 0 ]; then docker tag "$old_id" "$ROLLBACK" || die "couldn't tag the rollback image"; fi
recreate || die "docker compose up failed (old image tagged $ROLLBACK). Dagu is PAUSED"
if ! verify; then
    [ "$new_image" = 1 ] || die "recreated but didn't verify (same image, so no rollback). Dagu is PAUSED"
    log "rolling back to $ROLLBACK ($old_id)"
    docker tag "$ROLLBACK" "$image_ref" && recreate && verify \
        || die "the new image failed and so did the rollback to $old_ver. Dagu is PAUSED"
    die "the new image failed its check; rolled back to $old_ver, which is up and unpaused"
fi

# ---- record ------------------------------------------------------------------------
[ "$dry" = 1 ] || echo "$applied" >"$STAMP"
skipped=$(jq -r --arg from "$paused_at" --arg to "$(date -Iseconds)" \
    '.dags | to_entries[] | select(.value.nextRun != null and .value.nextRun >= $from and .value.nextRun < $to) | "\(.key) (\(.value.nextRun))"' \
    "$OUT/.state-at-pause.json" 2>/dev/null | paste -sd',' | sed 's/,/, /g')
msg="**Dagu** ${old_ver} → ${new_ver:-$old_ver}: recreated ($mode), reconciler green, scheduler resumed after $(( ($(date +%s) - $(date -d "$paused_at" +%s)) / 60 )) min paused."
[ -n "$skipped" ] && msg+=" Missed while paused (first tick of each, not replayed): $skipped."
log "$msg"
post ok "$msg"
