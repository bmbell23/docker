#!/bin/bash
# Get dockerhost (VM 101) ready for a graceful shutdown, and record what "running"
# looks like so verify-boot.sh can prove it all came back (docker#23, thread 015).
#
# It STOPS NOTHING. Containers are left for dockerd to stop during the systemd
# shutdown: a container you `docker stop` yourself stays down after boot
# (unless-stopped), which is the trap this avoids.
#
#   prep-shutdown.sh                  check now: SAFE, or what it's waiting on (exit 1)
#   prep-shutdown.sh --wait           wait for running work to finish, then SAFE
#   prep-shutdown.sh --wait --notify '@brandon'   ...and post the result to Mattermost
#   SKIP_BACKUPS=1 / POLL=60 (seconds between checks) / MAX_WAIT=14400 (give up after)
#
# "Running work" = Dagu job steps in flight (any `ssh dockerhost|proxmox` from the
# dagu container, which covers every DAG), MediaForge/backup scripts started by
# hand, and other agents' turns (this process's own ancestry is excluded).
# Exit codes: 0 SAFE TO SHUT DOWN, 1 BLOCKED (or --wait gave up), 3 WAITING ON (no --wait).
# Snapshot: ~/projects/docker/logs/shutdown-<ts>/  (logs/ is gitignored)

set -uo pipefail

WAIT_MODE=0; NOTIFY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --wait) WAIT_MODE=1 ;;
        --notify) NOTIFY="$2"; shift ;;
        *) echo "usage: $0 [--wait] [--notify <#channel|@user>]" >&2; exit 2 ;;
    esac
    shift
done
POLL="${POLL:-60}"; MAX_WAIT="${MAX_WAIT:-14400}"

REPO=/home/brandon/projects/docker
TS=$(date +%Y%m%d-%H%M%S)
SNAP_ROOT="${SNAP_ROOT:-$REPO/logs}"   # override for testing
SNAP="$SNAP_ROOT/shutdown-$TS"

blockers=()
warnings=()
say() { echo "[$(date +%H:%M:%S)] $*"; }
notify() { [ -n "$NOTIFY" ] && printf '%s\n' "$*" | /home/brandon/projects/agent-bus/bin/say dakota "$NOTIFY" - >/dev/null 2>&1; return 0; }

# PIDs of this script and everything above it (so an agent running it doesn't wait on itself).
ancestors() { local p=$$; while [ "$p" -gt 1 ]; do echo "$p"; p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null || echo 1); done; }

# What's still running, one item per line. Empty = quiet.
busy_now() {
    local self; self=$(ancestors | tr '\n' '|'); self="${self%|}"
    pgrep -af 'ssh (dockerhost|proxmox) ' | grep -vE '^[0-9]+ (bash|sh) ' | awk '{$1=""; print "dagu job:"$0}' | cut -c1-120
    pgrep -af 'align-cron|worker-cron|bin/audiobook|backup-databases|backup-db\.sh|stash-identify' \
        | grep -vE "^(${self}) " | grep -v pgrep | awk '{print "script: "$2" "$3" "$4}'
    pgrep -f 'claude -p' | grep -vxE "${self}" | while read -r pid; do
        name=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -oE -- '--name [^·]*' | cut -c8- | head -c 40)
        echo "agent turn: pid $pid ${name}"
    done
}

# 0. Wait (or report) until nothing is running.
start=$(date +%s); last=""
while :; do
    busy=$(busy_now)
    [ -z "$busy" ] && break
    if [ "$WAIT_MODE" != 1 ]; then
        echo "WAITING ON:"; echo "$busy" | sed 's/^/  /'
        echo "NOT SAFE YET. Re-run with --wait to wait for these and get told when it's safe."
        exit 3   # waiting (not blocked): callers may start a --wait watcher
    fi
    if [ "$busy" != "$last" ]; then
        say "waiting on:"; echo "$busy" | sed 's/^/  /'; last="$busy"
    fi
    if [ $(( $(date +%s) - start )) -ge "$MAX_WAIT" ]; then
        notify "prep-shutdown gave up after $((MAX_WAIT/60)) min. Still running: $(echo "$busy" | tr '\n' ';')"
        echo "GAVE UP after ${MAX_WAIT}s"; exit 1
    fi
    sleep "$POLL"
done
[ -n "$last" ] && say "everything finished"

mkdir -p "$SNAP"
say "snapshot -> $SNAP"

# 1. Containers: name, restart policy, state, health, published host ports.
docker ps -q | xargs -r docker inspect --format \
    '{{.Name}}	{{.HostConfig.RestartPolicy.Name}}	{{.State.Status}}	{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}	{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{.HostPort}}:{{$p}},{{end}}{{end}}' \
    | sed 's#^/##' | sort > "$SNAP/containers.tsv"
say "containers running: $(wc -l < "$SNAP/containers.tsv")"

# Running containers that won't restart on boot (no restart policy).
while IFS=$'\t' read -r name policy _ _ _; do
    case "$policy" in always|unless-stopped|on-failure) ;;
        *) warnings+=("$name has restart policy '${policy:-none}': it will NOT come back after boot") ;;
    esac
done < "$SNAP/containers.tsv"

# Unhealthy now = it won't be healthy after boot either; know that before, not after.
awk -F'\t' '$4=="unhealthy"{print $1}' "$SNAP/containers.tsv" | while read -r c; do
    echo "$c"; done > "$SNAP/unhealthy-before.txt"
[ -s "$SNAP/unhealthy-before.txt" ] && warnings+=("already unhealthy before shutdown: $(tr '\n' ' ' < "$SNAP/unhealthy-before.txt")")

# Published TCP ports that already don't answer: not the reboot's fault afterwards.
cut -f5 "$SNAP/containers.tsv" | tr ',' '\n' | grep -E '/tcp$' | cut -d: -f1 | sort -un | while read -r port; do
    timeout 3 bash -c "exec 3<>/dev/tcp/${HOST_IP:-10.0.0.160}/$port" 2>/dev/null || echo "$port"
done > "$SNAP/ports-dead-before.txt"
[ -s "$SNAP/ports-dead-before.txt" ] && warnings+=("published ports already not answering: $(tr '\n' ' ' < "$SNAP/ports-dead-before.txt")")

# 2. Mounts, enabled units, firewall.
findmnt -rn -o TARGET,SOURCE,FSTYPE | awk '$1 ~ /^\/mnt\// && $3 != "overlay"' > "$SNAP/mounts.txt"
systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | sort > "$SNAP/units-system.txt"
systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | sort > "$SNAP/units-user.txt"
if [ "${NO_SUDO:-0}" != 1 ] && sudo -n iptables-save > "$SNAP/iptables-save.txt" 2>/dev/null; then
    say "iptables saved"
else
    rm -f "$SNAP/iptables-save.txt"
    warnings+=("iptables not saved (needs passwordless sudo); stale-DNAT check after boot will be skipped")
fi

for u in agent-bus-router.service; do
    systemctl --user is-enabled "$u" >/dev/null 2>&1 \
        || blockers+=("user unit $u is not enabled: it will not start at boot")
done
grep -qx 'docker.service' "$SNAP/units-system.txt" || blockers+=("docker.service is not enabled")

# 4. Fresh database backups (the same scripts server-backups runs nightly).
if [ "${SKIP_BACKUPS:-0}" != "1" ]; then
    say "running database backups..."
    if "$REPO/scripts/backup/backup-databases.sh" > "$SNAP/backup-databases.log" 2>&1; then
        say "  databases ok"
    else
        blockers+=("backup-databases.sh failed (see $SNAP/backup-databases.log)")
    fi
    if /home/brandon/projects/GreatReads/greatreads/scripts/backup-db.sh > "$SNAP/backup-greatreads.log" 2>&1; then
        say "  greatreads ok"
    else
        blockers+=("GreatReads backup failed (see $SNAP/backup-greatreads.log)")
    fi
fi
# Immich dumps itself nightly; just make sure the newest dump is recent.
newest=$(ls -t /mnt/boston/media/pictures/immich-storage/backups/immich-db-backup-*.sql.gz 2>/dev/null | head -n 1)
if [ -z "$newest" ] || [ -n "$(find "$newest" -mmin +1560)" ]; then
    warnings+=("newest Immich DB dump is missing or older than 26h: ${newest:-none}")
else
    say "immich dump ok: $(basename "$newest")"
fi

# 5. Verdict.
{
    printf 'blockers:\n'; printf '  %s\n' "${blockers[@]:-none}"
    printf 'warnings:\n'; printf '  %s\n' "${warnings[@]:-none}"
} > "$SNAP/verdict.txt"
ln -sfn "$SNAP" "$SNAP_ROOT/shutdown-latest"

echo
for w in "${warnings[@]}"; do echo "WARN: $w"; done
if [ "${#blockers[@]}" -gt 0 ]; then
    for b in "${blockers[@]}"; do echo "BLOCKED: $b"; done
    echo "NOT SAFE TO SHUT DOWN (snapshot kept: $SNAP)"
    notify "prep-shutdown: NOT SAFE. $(printf '%s; ' "${blockers[@]}")"
    exit 1
fi
echo "SAFE TO SHUT DOWN. Snapshot: $SNAP"
notify "prep-shutdown: SAFE TO SHUT DOWN. $([ "${#warnings[@]}" -gt 0 ] && echo "${#warnings[@]} warning(s), see $SNAP/verdict.txt.") Next: on proxmox, qm shutdown 101 --timeout 300"
echo "After boot, run: $REPO/scripts/maintenance/verify-boot.sh"
