#!/usr/bin/env bash
# Recreate containers stuck in a dead network namespace (docker#165).
#
# A container with `network_mode: "container:mullvad-vpn"` (jackett, flaresolverr) is bound to the
# VPN container's ID when it is created. When the torrents stack recreates mullvad-vpn, they keep
# pointing at the old, gone ID: running, but no network. This finds every running container whose
# HostConfig.NetworkMode is container:<id-or-name> and <id-or-name> isn't a running container, and
# runs `docker compose up -d --no-deps --force-recreate <service>` in its compose dir (from its
# com.docker.compose.* labels). Without those labels it is reported and left alone.
# Used by container-updates.sh (after the stack loop) and the medic's `netns` playbook.
#
# One line per action. Exit 0: nothing orphaned, or all recreated. Exit 1: a recreate failed or an
# orphan was left untouched.
#
#   netns-orphans.sh [--dry-run]
set -uo pipefail

DOCKER="${DOCKER:-docker}"
dry=0
case "${1:-}" in
    "") ;;
    --dry-run) dry=1 ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

ids=$($DOCKER ps -q --no-trunc) || { echo "can't list containers"; exit 1; }
[ -n "$ids" ] || exit 0

# Running containers: full id, name, netmode, compose dir, compose service (tab-separated).
fmt='{{.Id}}'$'\t''{{.Name}}'$'\t''{{.HostConfig.NetworkMode}}'$'\t''{{index .Config.Labels "com.docker.compose.project.working_dir"}}'$'\t''{{index .Config.Labels "com.docker.compose.service"}}'
# shellcheck disable=SC2086
rows=$($DOCKER inspect --format "$fmt" $ids) || { echo "can't inspect containers"; exit 1; }

running=$'\n'
while IFS=$'\t' read -r id name _; do running+="$id"$'\n'"${name#/}"$'\n'; done <<<"$rows"

alive() {   # is $1 (a full id, a short id, or a name) a running container?
    case "$running" in *$'\n'"$1"$'\n'*) return 0 ;; esac
    [[ "$1" =~ ^[0-9a-f]{12,64}$ ]] || return 1
    case "$running" in *$'\n'"$1"*) return 0 ;; esac
    return 1
}

rc=0
while IFS=$'\t' read -r id name mode dir svc; do
    [[ "$mode" == container:* ]] || continue
    target=${mode#container:}
    alive "$target" && continue
    name=${name#/}
    if [ -z "$dir" ] || [ -z "$svc" ]; then
        echo "$name: shares dead namespace ${target:0:12} but has no compose labels; left untouched"
        rc=1; continue
    fi
    if [ "$dry" = 1 ]; then
        echo "$name: shares dead namespace ${target:0:12}; would run: (cd $dir && docker compose up -d --no-deps --force-recreate $svc)"
    elif (cd "$dir" && $DOCKER compose up -d --no-deps --force-recreate "$svc") >/dev/null 2>&1; then
        echo "$name: shared dead namespace ${target:0:12}; recreated ($svc)"
    else
        echo "$name: shares dead namespace ${target:0:12}; recreate of $svc in $dir FAILED"
        rc=1
    fi
done <<<"$rows"
exit $rc
