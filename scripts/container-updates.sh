#!/usr/bin/env bash
# Weekly updates for the off-the-shelf stacks in dagu/update-stacks.yaml (docker#37).
# Run by dagu/dags/container-updates.yaml on the host over ssh.
#
# Per stack, one at a time:
#   1. Ask the registry whether a newer image exists for any of its compose images (no pull).
#      Nothing newer: done. mode notify/hold: report it, done.
#   2. Health check BEFORE touching it: a stack that's already broken is skipped and reported,
#      so the update never gets blamed for it (or "fixed" by a revert).
#   3. pre hook (a backup). If it fails, the stack is not updated.
#   4. Tag what runs now as updates-rollback/<stack>:<image>. That keeps the old image from
#      the daily prune and is what a revert goes back to. Then pull and `up -d`.
#   5. post hook (migrations), then the health check: every container running, healthy where it
#      has a healthcheck, every published TCP port answering on localhost, and still so 30 s later.
#   6. Failed: retag the old images, `up -d` again, check again. If even that fails, the stack
#      goes on hold (logs/updates/.hold-<stack>) and @brandon gets the restore pointer.
#      A database the new version already migrated is NOT restored automatically (docker#37):
#      that overwrites data, so it's Brandon's call.
#
# One summary to #infra as Biscuit. Exit 1 if anything was reverted, held or broken.
#
#   container-updates.sh [--dry-run] [--only <stack>]
#   container-updates.sh --check <stack>     just the health check, read-only
set -uo pipefail

ROOT="${UPDATES_ROOT:-/home/brandon/projects/docker}"
REG="${UPDATES_REGISTRY:-$ROOT/dagu/update-stacks.yaml}"
OUT="${UPDATES_OUT:-$ROOT/logs/updates}"
SAY="${UPDATES_SAY:-/home/brandon/projects/agent-bus/bin/say}"
CHANNEL="${UPDATES_CHANNEL:-#infra}"
WAIT="${UPDATES_WAIT:-180}"
dry=0; only=""; check=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry=1 ;;
        --only) only="${2:?--only needs a stack}"; shift ;;
        --check) check="${2:?--check needs a stack}"; shift ;;
        *) echo "usage: $0 [--dry-run] [--only <stack>] | --check <stack>" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "$OUT"
exec 9>"$OUT/.lock"
flock -n 9 || { echo "another container-updates run is going"; exit 0; }
log="$OUT/$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$log") 2>&1
ls -1t "$OUT"/*.log 2>/dev/null | tail -n +21 | xargs -r rm -f

rows=$(python3 - "$REG" <<'EOF'
import sys, yaml
for s in yaml.safe_load(open(sys.argv[1]))["stacks"]:
    f = [s["name"], s.get("mode", "notify"), s.get("pre") or "-", s.get("post") or "-", s.get("why") or "-"]
    print("\t".join(str(x).replace("\t", " ").replace("\n", " ") for x in f))
EOF
) || { echo "can't read $REG"; exit 1; }

updated=(); available=(); reverted=(); problems=()

compose() { (cd "$ROOT/$name" && docker compose "$@"); }
ids() { compose ps -aq 2>/dev/null; }
short() { local r=${1##*/}; echo "${r%%:*}"; }
ver() {   # ver <image ref or id>: the image's version label, else its short id
    local v
    v=$(docker image inspect "$1" --format '{{with index .Config.Labels "org.opencontainers.image.version"}}{{.}}{{else}}{{with index .Config.Labels "build_version"}}{{.}}{{end}}{{end}}' 2>/dev/null)
    [ -n "$v" ] && { echo "${v#Linuxserver.io version: }" | cut -d' ' -f1; return; }
    docker image inspect "$1" --format '{{.Id}}' 2>/dev/null | cut -c8-19
}
vers() { local r out=(); for r in "$@"; do out+=("$(short "$r") $(ver "$r")"); done; local IFS=,; echo "${out[*]}" | sed 's/,/, /g'; }
newer_than_local() {   # 0 = newer exists (in the registry, or pulled but not running), 1 = same, 2 = couldn't ask
    local rd have tagid c
    tagid=$(docker image inspect "$1" --format '{{.Id}}' 2>/dev/null)
    for c in $(ids); do   # pulled outside this job: the tag moved but the container didn't
        [ "$(docker inspect "$c" --format '{{.Config.Image}}')" = "$1" ] && [ "$(docker inspect "$c" --format '{{.Image}}')" != "$tagid" ] && return 0
    done
    rd=$(timeout 60 docker buildx imagetools inspect "$1" 2>/dev/null | awk '/^Digest:/{print $2; exit}')
    [ -n "$rd" ] || return 2
    have=$(docker image inspect "$1" --format '{{join .RepoDigests "\n"}}' 2>/dev/null | sed 's/.*@//')
    grep -qx "$rd" <<<"$have" && return 1
    return 0
}

check_once() {   # check_once: sets bad (empty = fine) and sig (restart counts)
    local c st hl n rc b ip port ok a
    bad=""; sig=""
    mapfile -t cs < <(ids)
    [ ${#cs[@]} -gt 0 ] || { bad="no containers"; return; }
    for c in "${cs[@]}"; do
        IFS='|' read -r st hl n rc < <(docker inspect "$c" --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}|{{.Name}}|{{.RestartCount}}')
        sig+="$c=$rc "
        [ "$st" = running ] || { bad="${n#/} is $st"; return; }
        if [ "$hl" = starting ] || [ "$hl" = unhealthy ]; then bad="${n#/} health: $hl"; return; fi
        # one line per published TCP port, all its bindings; it passes if any binding answers
        while read -r b; do
            [ -n "$b" ] || continue
            ok=0
            for ip in ${b#*=}; do
                port=${ip##*:}; ip=${ip%:*}
                # All-interfaces bindings: the LAN IP, like verify-boot. Some ports here have no
                # docker-proxy listener and only answer via DNAT, so 127.0.0.1 times out (immich).
                case "$ip" in ""|0.0.0.0|::|"[::]") ip="${HOST_IP:-10.0.0.160} 127.0.0.1" ;; esac
                for a in $ip; do timeout 3 bash -c "exec 3<>/dev/tcp/$a/$port" 2>/dev/null && { ok=1; break 2; }; done
            done
            [ "$ok" = 1 ] || { bad="${n#/} port ${b%%=*} not answering"; return; }
        done < <(docker inspect "$c" --format '{{range $k, $v := .NetworkSettings.Ports}}{{if $v}}{{$k}}={{range $v}}{{.HostIp}}:{{.HostPort}} {{end}}{{"\n"}}{{end}}{{end}}' | grep '/tcp=')
    done
}

healthy() {   # healthy <seconds>: two clean checks 30 s apart, same restart counts; else why_bad
    local deadline=$(( $(date +%s) + $1 )) first
    why_bad=""
    while :; do
        check_once
        if [ -z "$bad" ]; then
            first=$sig; sleep 30; check_once
            [ -z "$bad" ] && [ "$sig" = "$first" ] && return 0
            [ -n "$bad" ] || bad="restarted within 30 s of looking healthy"
        fi
        [ "$(date +%s)" -ge "$deadline" ] && { why_bad=$bad; return 1; }
        sleep 10
    done
}

recreate() {   # up -d; if compose can't stop a container here, the server's kill + up -d method
    local out
    out=$(compose up -d --pull never 2>&1); local rc=$?; echo "$out"
    [ $rc = 0 ] && return 0
    grep -qi 'permission denied' <<<"$out" || return 1
    echo "$name: up -d couldn't stop a container; trying kill + up -d"
    for c in $(ids); do
        pid=$(docker inspect "$c" --format '{{.State.Pid}}'); [ "${pid:-0}" -gt 0 ] && kill "$pid" 2>/dev/null
    done
    sleep 5
    compose up -d --pull never
}

revert() {   # revert <reason>
    local ref
    why_bad=""
    echo "$name: $1; reverting"
    for ref in "${!old[@]}"; do docker tag "${old[$ref]}" "$ref"; done
    if recreate && healthy "$WAIT"; then
        reverted+=("$name: update failed ($1); back on ${was[*]} and healthy")
    else
        echo "$1 / revert: ${why_bad:-up -d failed}" > "$OUT/.hold-$name"
        problems+=("$name: update failed ($1) AND the revert isn't healthy (${why_bad:-up -d failed}). On hold. If the new version migrated its database, the old one may not read it: restore from the pre-update backup${pre:+ (\`$pre\`)}; not done automatically")
    fi
}

if [ -n "$check" ]; then name=$check; healthy 60 && { echo "$name: healthy"; exit 0; }; echo "$name: $why_bad"; exit 1; fi

while IFS=$'\t' read -r name mode pre post why <&3; do
    [ -z "$only" ] || [ "$name" = "$only" ] || continue
    [ "$pre" = - ] && pre=""; [ "$post" = - ] && post=""; [ "$why" = - ] && why=""
    echo "== $name ($mode)"
    [ -f "$ROOT/$name/docker-compose.yml" ] || [ -f "$ROOT/$name/compose.yaml" ] || { problems+=("$name: no compose file in $ROOT/$name"); continue; }
    [ -f "$OUT/.hold-$name" ] && { problems+=("$name: on hold since a failed revert ($(cat "$OUT/.hold-$name")); delete $OUT/.hold-$name to resume"); continue; }

    newer=(); unknown=()
    while read -r ref; do
        [ -n "$ref" ] || continue
        newer_than_local "$ref"; case $? in 0) newer+=("$ref") ;; 2) unknown+=("$ref") ;; esac
    done < <(compose config --images 2>/dev/null | sort -u)
    [ ${#unknown[@]} -gt 0 ] && problems+=("$name: couldn't ask the registry about ${unknown[*]}")
    [ ${#newer[@]} -gt 0 ] || { echo "$name: current"; continue; }
    if [ "$mode" != auto ]; then
        available+=("$name ($mode): newer image than $(vers "${newer[@]}")${why:+ ($why)}")
        continue
    fi
    if [ "$dry" = 1 ]; then available+=("$name: would update $(vers "${newer[@]}")"); continue; fi

    healthy 60 || { problems+=("$name: not healthy before the update ($why_bad); left alone"); continue; }
    if [ -n "$pre" ]; then
        bash -c "$pre" || { problems+=("$name: pre-update backup failed (\`$pre\`); not updated"); continue; }
    fi

    declare -A old=(); was=()
    for c in $(ids); do
        ref=$(docker inspect "$c" --format '{{.Config.Image}}'); id=$(docker inspect "$c" --format '{{.Image}}')
        [ -n "${old[$ref]:-}" ] && continue
        old[$ref]=$id; was+=("$(short "$ref") $(ver "$id")")
        docker tag "$id" "updates-rollback/$name:$(tr -c 'a-zA-Z0-9_.-' '_' <<<"$ref" | cut -c1-100)"
    done
    if ! compose pull -q; then   # a half-done pull may have moved a tag: put it back
        for ref in "${!old[@]}"; do docker tag "${old[$ref]}" "$ref"; done
        problems+=("$name: pull failed; tags put back, nothing changed"); continue
    fi
    # What up -d will change: each container's running image vs its service's image in the
    # compose file (also catches a compose-file tag change, e.g. mariadb:latest -> 12.2)
    changes=(); cfg=$(compose config --format json 2>/dev/null)
    for c in $(ids); do
        svc=$(docker inspect "$c" --format '{{index .Config.Labels "com.docker.compose.service"}}')
        want=$(jq -r --arg s "$svc" '.services[$s].image // empty' <<<"$cfg")
        cur=$(docker inspect "$c" --format '{{.Image}}'); nid=$(docker image inspect "$want" --format '{{.Id}}' 2>/dev/null)
        [ -n "$nid" ] && [ "$nid" != "$cur" ] && changes+=("$(short "$want") $(ver "$cur") → $(ver "$nid")")
    done
    [ ${#changes[@]} -gt 0 ] || { echo "$name: pull brought nothing new"; continue; }

    recreate || { revert "up -d failed"; continue; }
    if [ -n "$post" ] && ! bash -c "$post"; then   # never revert under a half-run migration
        echo "post hook failed: $post" > "$OUT/.hold-$name"
        problems+=("$name: post hook failed (\`$post\`); left on the NEW image ($(printf '%s ' "${changes[@]}")), on hold. Not reverted: it may be mid-migration")
        continue
    fi
    healthy "$WAIT" || { revert "$why_bad"; continue; }
    updated+=("$name: ${changes[*]}")
done 3<<<"$rows"

msg="**Weekly container updates**$([ "$dry" = 1 ] && echo ' (dry run)')"
[ ${#problems[@]} -gt 0 ] || [ ${#reverted[@]} -gt 0 ] && msg="@brandon $msg"
for l in "${updated[@]}";   do msg+=$'\n'"- updated $l"; done
for l in "${reverted[@]}";  do msg+=$'\n'"- REVERTED $l"; done
for l in "${problems[@]}";  do msg+=$'\n'"- PROBLEM $l"; done
for l in "${available[@]}"; do msg+=$'\n'"- $l"; done
[ ${#updated[@]} -eq 0 ] && [ ${#reverted[@]} -eq 0 ] && [ ${#problems[@]} -eq 0 ] && [ ${#available[@]} -eq 0 ] && msg+=$'\n'"- everything current"
echo; echo "$msg"
if [ "$dry" = 0 ]; then
    printf '%s\n' "$msg" | "$SAY" biscuit "$CHANNEL" - \
        || { echo "POST FAILED" >&2; logger -t container-updates "summary post failed"; }
fi
[ ${#problems[@]} -eq 0 ] && [ ${#reverted[@]} -eq 0 ]
