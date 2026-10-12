#!/usr/bin/env bash
# netns-orphans.sh against a fake docker (docker#165): containers sharing a network namespace
# that no longer exists get recreated from their compose labels; the rest is left alone.
# Run: tests/netns-orphans.test.sh   (no Docker needed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
VPN=$(printf 'a%.0s' {1..64}); DEAD=$(printf 'd%.0s' {1..64})

# Fake docker: `ps -q` prints $T/ids; `inspect --format F id...` prints $T/rows/<id> (tab-separated:
# id name netmode dir service) for each; `compose ...` is logged, and fails if $T/up-fails exists.
cat >"$T/docker" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
ps) cat "$FAKE_T/ids" ;;
inspect) shift 3; for id in "$@"; do cat "$FAKE_T/rows/$id"; done ;;
compose) echo "$PWD: $*" >>"$FAKE_T/docker.log"; [ ! -e "$FAKE_T/up-fails" ] ;;
esac
FAKE
chmod +x "$T/docker"
export DOCKER="$T/docker" FAKE_T="$T"
mkdir -p "$T/rows" "$T/jackett"

fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
row() { printf '%s\t/%s\t%s\t%s\t%s\n' "$2" "$1" "$3" "${4:-}" "${5:-}" >"$T/rows/$2"; }   # name id mode dir svc
reset() { rm -f "$T/docker.log" "$T/up-fails"; : >"$T/ids"; rm -f "$T"/rows/*; }
add() { echo "$2" >>"$T/ids"; row "$@"; }
run() { out=$("$HERE/scripts/netns-orphans.sh" "$@" 2>&1); rc=$?; }

reset
add mullvad-vpn "$VPN" bridge
add jackett "$(printf 'b%.0s' {1..64})" "container:$VPN" "$T/jackett" jackett
add flaresolverr "$(printf 'c%.0s' {1..64})" "container:mullvad-vpn" "$T/jackett" flaresolverr
run
check "healthy sharers (by id and by name): exit 0, no output, no compose" '[ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$T/docker.log" ]' || echo "$out"

reset
add mullvad-vpn "$VPN" bridge
add jackett "$(printf 'b%.0s' {1..64})" "container:$DEAD" "$T/jackett" jackett
run
check "orphan with labels: exit 0" '[ $rc = 0 ]' || echo "$out"
check "orphan with labels: one up --force-recreate --no-deps, in its dir" '[ "$(cat "$T/docker.log")" = "$T/jackett: compose up -d --no-deps --force-recreate jackett" ]'
check "orphan with labels: one line of output" '[ "$(wc -l <<<"$out")" = 1 ] && grep -q "^jackett: .*recreated" <<<"$out"'

reset
add jackett "$(printf 'b%.0s' {1..64})" "container:$DEAD" "$T/jackett" jackett
touch "$T/up-fails"
run
check "failed recreate: exit 1 and says FAILED" '[ $rc = 1 ] && grep -q FAILED <<<"$out"'

reset
add stray "$(printf 'b%.0s' {1..64})" "container:$DEAD"
run
check "orphan without labels: exit 1, reported, untouched" '[ $rc = 1 ] && grep -q "^stray: .*no compose labels" <<<"$out" && [ ! -e "$T/docker.log" ]'

reset
add jackett "$(printf 'b%.0s' {1..64})" "container:$DEAD" "$T/jackett" jackett
run --dry-run
check "--dry-run: says what it would do, exit 0, runs nothing" '[ $rc = 0 ] && grep -q "would run.*--force-recreate jackett" <<<"$out" && [ ! -e "$T/docker.log" ]' || echo "$out"

exit $fail
