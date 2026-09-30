#!/bin/bash
# Delete nat DOCKER-chain DNAT rules that point at an IP no running container has
# (docker#34): the "works on 127.0.0.1, times out on Tailscale" failure.
#
#   scripts/maintenance/clean-stale-dnat.sh [--dry-run]
#   Runs at boot from docker-post-boot.sh (as root); by hand it uses sudo -n.
#
# Only DNAT rules whose destination IP is missing from every running container
# are touched; Docker re-creates any rule it owns when its container starts.

set -uo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
SUDO=""
[ "$(id -u)" = 0 ] || SUDO="sudo -n"

rules=$($SUDO iptables -t nat -S DOCKER) || { echo "FAILED: can't read the nat DOCKER chain (needs root)" >&2; exit 1; }
ips=$(docker ps -q | xargs -r docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' \
    | tr ' ' '\n' | grep -v '^$' | sort -u)
[ -n "$ips" ] || { echo "FAILED: no running container has an IP; not judging rules against nothing" >&2; exit 1; }

n=0
while IFS= read -r rule; do
    ip=$(grep -oE -- '--to-destination [0-9.]+' <<<"$rule" | awk '{print $2}')
    [ -n "$ip" ] || continue
    grep -qxF "$ip" <<<"$ips" && continue
    n=$((n + 1))
    if [ "$DRY" = 1 ]; then
        echo "would delete: $rule"
    else
        # -S prints "-A DOCKER ..."; the same spec with -D deletes exactly that rule.
        read -ra spec <<<"${rule/#-A /-D }"
        if $SUDO iptables -t nat "${spec[@]}"; then echo "deleted: $rule"; else echo "FAILED to delete: $rule" >&2; fi
    fi
done < <(grep -- '-j DNAT' <<<"$rules")

echo "$n stale DNAT rule(s) $([ "$DRY" = 1 ] && echo found || echo handled)"
