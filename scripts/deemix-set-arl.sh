#!/bin/bash
# One-step Deezer ARL renewal for deemix (docker#42).
#   deemix-set-arl.sh               prompts for the new ARL (hidden), or reads it from stdin
#   deemix-set-arl.sh --check-only  validate the ARL and stop; writes and restarts nothing
# Validates against Deezer BEFORE writing, so a typo can't replace a working ARL. Then it
# writes login.json (keeping login.json.bak, same perms) and .arl if present, and restarts
# deemix. `docker restart` is denied on this server, hence kill + compose up.
# The ARL is a secret: never on a command line, never printed.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CONFIG_DIR="${DEEMIX_CONFIG:-/home/brandon/projects/docker/deemix/config}"
COMPOSE_DIR=/home/brandon/projects/docker/deemix

check_only=0
[ "${1:-}" = "--check-only" ] && check_only=1

if [ -t 0 ]; then
    read -rsp "New Deezer ARL (hidden): " arl
    echo
else
    IFS= read -r arl
fi
arl="${arl//[[:space:]]/}"
[ -n "$arl" ] || { echo "No ARL given." >&2; exit 1; }

printf '%s\n' "$arl" | "$HERE/deemix-arl-check.sh" --stdin || {
    rc=$?
    echo "Not writing anything; the current ARL is untouched." >&2
    exit $rc
}
[ $check_only -eq 1 ] && exit 0

login="$CONFIG_DIR/login.json"
tmp=$(mktemp "$login.XXXXXX") || exit 1
trap 'rm -f "$tmp"' EXIT
cp -p "$login" "$login.bak" || { echo "Can't make $login.bak" >&2; exit 1; }
if ! printf '%s' "$arl" | jq --rawfile a /dev/stdin '.arl = ($a | rtrimstr("\n"))' "$login" > "$tmp"; then
    echo "jq failed; login.json untouched." >&2
    exit 1
fi
chmod --reference="$login" "$tmp"
mv "$tmp" "$login"
echo "Wrote login.json (previous kept as login.json.bak)"

if [ -f "$CONFIG_DIR/.arl" ]; then
    atmp=$(mktemp "$CONFIG_DIR/.arl.XXXXXX") || exit 1
    printf '%s\n' "$arl" > "$atmp"
    chmod --reference="$CONFIG_DIR/.arl" "$atmp"
    mv "$atmp" "$CONFIG_DIR/.arl"
    echo "Wrote .arl"
fi
unset arl

PID=$(docker inspect deemix --format '{{.State.Pid}}')
if [ -n "$PID" ] && [ "$PID" != 0 ]; then
    kill "$PID"
fi
cd "$COMPOSE_DIR" && docker compose up -d
echo "deemix restarted"
