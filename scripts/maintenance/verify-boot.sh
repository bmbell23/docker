#!/bin/bash
# Prove dockerhost came back the way prep-shutdown.sh recorded it (docker#23).
#
#   scripts/maintenance/verify-boot.sh [--notify <#channel|@user>] [snapshot-dir]
#                                                       default snapshot: logs/shutdown-latest
#   Runs by itself once per boot via systemd/verify-boot.service (--notify @brandon).
#   WAIT=300 scripts/maintenance/verify-boot.sh         retry window for slow starters (s)
#
# One line per failure; exit 0 only if everything matches.

set -uo pipefail

REPO=/home/brandon/projects/docker
NOTIFY=""
if [ "${1:-}" = "--notify" ]; then NOTIFY="$2"; shift 2; fi
SNAP="${1:-$REPO/logs/shutdown-latest}"
notify() {
    [ -n "$NOTIFY" ] || return 0
    # Posts as @biscuit (the script bot). bin/say waits up to SAY_WAIT s for Mattermost;
    # a failure is logged, never silently dropped (docker#35: the first boot DM was lost).
    local err
    if ! err=$(printf '%s\n' "$*" | /home/brandon/projects/agent-bus/bin/say biscuit "$NOTIFY" - 2>&1 >/dev/null); then
        echo "NOTIFY FAILED (Mattermost post to $NOTIFY): ${err:-no reason given}" >&2
        logger -t "$(basename "$0")" "notify to $NOTIFY failed: ${err:-no reason given}" 2>/dev/null || true
    fi
    return 0
}
WAIT="${WAIT:-300}"
[ -f "$SNAP/containers.tsv" ] || { echo "FAIL: no snapshot at $SNAP (run prep-shutdown.sh before shutting down)"; exit 2; }

fails=()
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; fails+=("$*"); }

tcp_open() { timeout 3 bash -c "exec 3<>/dev/tcp/${HOST_IP:-10.0.0.160}/$1" 2>/dev/null; }

# 1. Storage first: containers judged on an empty /mnt/boston would be lies.
while read -r target _ _; do
    if ! findmnt -rn "$target" >/dev/null; then
        fail "$target is not mounted"
    elif [ "$(timeout 10 df --output=used "$target" 2>/dev/null | tail -n 1 | tr -d ' ')" -lt 1048576 ] 2>/dev/null; then
        # df, not ls: /mnt/docker is root-only, but "used" works for anyone.
        fail "$target is mounted but (nearly) empty or not answering"
    else
        ok "$target mounted"
    fi
done < "$SNAP/mounts.txt"
if [ "${#fails[@]}" -gt 0 ]; then
    echo "STOP: storage is wrong. Containers that bind-mount it may be running on empty local dirs."
    echo "Do not judge the containers yet; fix the mount, then restart the affected containers."
    notify "verify-boot: STORAGE IS WRONG after boot. $(printf '%s; ' "${fails[@]}") Containers that use it may be running on empty folders."
    exit 1
fi

# 2. Containers: running, and healthy where they have a healthcheck. Retry until WAIT.
deadline=$(( $(date +%s) + WAIT ))
while :; do
    pending=()
    while IFS=$'\t' read -r name policy _ health_before _; do
        case "$policy" in always|unless-stopped|on-failure) ;; *) continue ;; esac
        state=$(docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$name" 2>/dev/null || echo "missing|-")
        st=${state%%|*}; hl=${state##*|}
        if [ "$st" != running ]; then pending+=("$name is $st")
        elif [ "$hl" = starting ]; then pending+=("$name health: starting")
        elif [ "$hl" = unhealthy ] && [ "$health_before" != unhealthy ]; then pending+=("$name is unhealthy")
        fi
    done < "$SNAP/containers.tsv"
    [ "${#pending[@]}" -eq 0 ] && break
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 10
done
for p in "${pending[@]}"; do fail "$p"; done
[ "${#pending[@]}" -eq 0 ] && ok "all $(awk -F'\t' '$2 ~ /always|unless-stopped|on-failure/' "$SNAP/containers.tsv" | wc -l) restartable containers running (and healthy where checked)"
[ -s "$SNAP/unhealthy-before.txt" ] && echo "note already unhealthy before shutdown, not counted: $(tr '\n' ' ' < "$SNAP/unhealthy-before.txt")"

# 3. Every published host port answers on localhost.
# Entries are hostport:containerport/proto; only TCP can be probed (1900/udp etc. can't).
cut -f5 "$SNAP/containers.tsv" | tr ',' '\n' | grep -E '/tcp$' | cut -d: -f1 | sort -un > "$SNAP/.ports"
bad=0
while read -r port; do
    tcp_open "$port" && continue
    if grep -qx "$port" "$SNAP/ports-dead-before.txt" 2>/dev/null; then
        echo "note port $port still not answering (it already wasn't before shutdown)"
    else
        fail "port $port does not answer on ${HOST_IP:-10.0.0.160}"; bad=1
    fi
done < "$SNAP/.ports"
[ "$bad" = 0 ] && ok "published TCP ports answer (checked $(wc -l < "$SNAP/.ports"); pre-existing failures noted above)"

# 4. No DNAT rule points at an IP no container has (the "works on 127.0.0.1,
#    times out on Tailscale" failure).
if [ "${NO_SUDO:-0}" != 1 ] && nat=$(sudo -n iptables-save -t nat 2>/dev/null); then
    ips=$(docker ps -q | xargs -r docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' | tr ' ' '\n' | grep -v '^$' | sort -u)
    stale=$(echo "$nat" | grep -oE 'DNAT .*--to-destination [0-9.]+' | grep -oE '[0-9.]+$' | sort -u | grep -vxF "$ips" || true)
    if [ -n "$stale" ]; then fail "stale DNAT rules point at: $(echo "$stale" | tr '\n' ' ')"; else ok "no stale DNAT rules"; fi
else
    echo "skip DNAT check (needs passwordless sudo): sudo iptables-save | grep DNAT"
fi

# 5. The office.
systemctl --user is-active --quiet agent-bus-router && ok "agent-bus-router active" || fail "agent-bus-router is not active"
tcp_open 8015 && ok "Mattermost :8015 answers" || fail "Mattermost :8015 does not answer"

# 6. Units that were enabled are still enabled.
missing=$(comm -23 "$SNAP/units-system.txt" <(systemctl list-unit-files --state=enabled --no-legend | awk '{print $1}' | sort))
[ -n "$missing" ] && fail "system units no longer enabled: $(echo "$missing" | tr '\n' ' ')"

echo
if [ "${#fails[@]}" -gt 0 ]; then
    echo "NOT CLEAN: ${#fails[@]} problem(s) above."
    notify "verify-boot: NOT CLEAN, ${#fails[@]} problem(s): $(printf '%s; ' "${fails[@]}")"
    exit 1
fi
echo "CLEAN BOOT: everything in $SNAP is back."
notify "verify-boot: CLEAN BOOT. Everything from $(basename "$(readlink -f "$SNAP")") is back."
