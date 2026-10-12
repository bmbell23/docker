#!/usr/bin/env bash
# deploy_medic from ./deploy against a fake systemctl in a throwaway git repo (docker#168):
# a changed medic.py restarts the unit, a broken one doesn't, first sight only stamps.
# Run: tests/deploy-medic.test.sh   (no systemd, no network; nothing real is restarted)
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Pull just the helpers and deploy_medic out of ./deploy (the rest talks to docker).
{ sed -n '/^stamp_ok() {/,/^}/p;/^stamp() {/,/^}/p;/^deploy_medic() {/,/^}/p' "$HERE/deploy"; } >"$T/funcs.sh"
grep -q '^deploy_medic()' "$T/funcs.sh" || { echo "FAIL deploy_medic not found in ./deploy"; exit 1; }

# Fake systemctl: logs every call; FAKE_NOUNIT / FAKE_NOSTART / FAKE_INACTIVE steer it.
cat >"$T/systemctl" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_LOG"
case "$2" in
cat) [ -z "${FAKE_NOUNIT:-}" ] ;;
restart) [ -z "${FAKE_NOSTART:-}" ] ;;
is-active) [ -z "${FAKE_INACTIVE:-}" ] ;;
esac
FAKE
chmod +x "$T/systemctl"
export SYSTEMCTL="$T/systemctl" FAKE_LOG="$T/calls" XDG_RUNTIME_DIR="$T"

R="$T/repo"; mkdir -p "$R/scripts/medic"; cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo 'print("v1")' >scripts/medic/medic.py; echo 'a: 1' >scripts/medic/targets.yaml
git add -A && git commit -qm v1
# shellcheck disable=SC1091
. "$T/funcs.sh"

fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
restarts() { grep -c -- '--user restart medic' "$FAKE_LOG" 2>/dev/null; true; }
commit() { git add -A && git commit -qm "$1"; }

out=$(FAKE_NOUNIT=1 deploy_medic); rc=$?
check "no unit -> rc 0, says so, no stamp" '[ $rc = 0 ] && [[ $out == *"no medic.service"* ]] && [ ! -e logs/deploy/medic-applied.sha256 ]'

out=$(deploy_medic); rc=$?
check "first sight -> stamped, not restarted" '[ $rc = 0 ] && [ "$out" = "medic: first sight; stamped, not restarted" ] && [ -f logs/deploy/medic-applied.sha256 ] && [ "$(restarts)" = 0 ]'

out=$(deploy_medic); rc=$?
check "unchanged -> rc 0, no restart" '[ $rc = 0 ] && [ "$out" = "medic: unchanged since the last apply" ] && [ "$(restarts)" = 0 ]'

echo 'b: 2' >scripts/medic/targets.yaml; commit targets
out=$(deploy_medic)
check "targets.yaml change alone -> unchanged, no restart" '[ "$out" = "medic: unchanged since the last apply" ] && [ "$(restarts)" = 0 ]'

echo 'print("broken"' >scripts/medic/medic.py; commit broken
before=$(cat logs/deploy/medic-applied.sha256)
out=$(deploy_medic); rc=$?
check "broken medic.py -> rc 1, not restarted, not stamped" '[ $rc = 1 ] && [[ $out == *"doesn'"'"'t compile"* ]] && [ "$(restarts)" = 0 ] && [ "$(cat logs/deploy/medic-applied.sha256)" = "$before" ]'
check "compile check left no __pycache__" '[ ! -e scripts/medic/__pycache__ ]'

echo 'print("v2")' >scripts/medic/medic.py; commit v2
out=$(FAKE_NOSTART=1 deploy_medic); rc=$?
check "restart fails -> rc 1, not stamped" '[ $rc = 1 ] && [ "$(cat logs/deploy/medic-applied.sha256)" = "$before" ]'

sleep() { :; }   # don't really wait 10 s
out=$(FAKE_INACTIVE=1 deploy_medic); rc=$?
check "never active -> rc 1, not stamped" '[ $rc = 1 ] && [[ $out == *"isn'"'"'t active"* ]] && [ "$(cat logs/deploy/medic-applied.sha256)" = "$before" ]'

: >"$FAKE_LOG"
out=$(deploy_medic); rc=$?
check "changed medic.py -> compiled, restarted, stamped" '[ $rc = 0 ] && [ "$out" = "medic: medic.py changed; restarted (journalctl --user -u medic)" ] && [ "$(restarts)" = 1 ] && stamp_ok medic scripts/medic/medic.py'
out=$(deploy_medic)
check "and again -> unchanged" '[ "$out" = "medic: unchanged since the last apply" ] && [ "$(restarts)" = 1 ]'

[ $fail = 0 ] && echo "PASS" || echo "FAILED"
exit $fail
