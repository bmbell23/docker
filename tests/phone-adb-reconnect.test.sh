#!/usr/bin/env bash
# phone-adb-reconnect.sh against fake adb / tailscale / nc (docker#173).
# Run: tests/phone-adb-reconnect.test.sh   (no phone, no network needed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"

# Fake adb: devices list in $T/devices ("serial state" lines). `connect host:port` adds the
# serial in state $T/connect_state (if the port is in $T/open); `disconnect` removes it.
cat >"$T/bin/adb" <<'FAKE'
#!/usr/bin/env bash
echo "adb $*" >>"$T/calls"
case "$1" in
devices) echo "List of devices attached"; awk '{ print $1 "\t" $2 }' "$T/devices" ;;
connect) grep -qx "${2##*:}" "$T/open" && echo "$2 $(cat "$T/connect_state")" >>"$T/devices" ;;
disconnect) grep -v "^$2 " "$T/devices" >"$T/d2"; mv "$T/d2" "$T/devices" ;;
esac
FAKE
cat >"$T/bin/tailscale" <<'FAKE'
#!/usr/bin/env bash
[ "$(cat "$T/ping")" = offline ] && { echo "no reply"; exit 1; }
echo "pong from phone (100.78.213.32) via $(cat "$T/ping") in 40ms"
FAKE
cat >"$T/bin/nc" <<'FAKE'
#!/usr/bin/env bash
grep -qx "${!#}" "$T/open"
FAKE
printf '#!/bin/sh\n' >"$T/bin/sleep"
chmod +x "$T/bin/"*
export T PATH="$T/bin:$PATH" PHONE_PORTS="40000 40020" PHONE_ADB_STATE="$T/state"

pass=0; failn=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
setup() { : >"$T/devices"; : >"$T/calls"; : >"$T/open"; echo device >"$T/connect_state"; echo "10.0.0.253:33179" >"$T/ping"; rm -rf "$T/state"; }
run() { out=$("$HERE/scripts/phone-adb-reconnect.sh" 2>&1); rc=$?; }

# Already connected: silent, no scan.
setup; echo "100.78.213.32:33709 device" >"$T/devices"; run
check "connected: output" "$out" ""; check "connected: rc" "$rc" 0
check "connected: no connect" "$(grep -c connect "$T/calls")" 0

# Port moved: old serial offline, new port open -> drop the old one, reconnect, one line.
setup; echo "100.78.213.32:44347 offline" >"$T/devices"; echo 40007 >"$T/open"; run
check "moved: output" "$out" "reconnected: 100.78.213.32:40007"; check "moved: rc" "$rc" 0
check "moved: old serial gone" "$(grep -c 44347 "$T/devices")" 0
check "moved: new serial" "$(cat "$T/devices")" "100.78.213.32:40007 device"

# Phone off Tailscale: quiet, no scan, no failure counted.
setup; echo offline >"$T/ping"; run
check "offline: output" "$out" ""; check "offline: rc" "$rc" 0; check "offline: no count" "$(cat "$T/state/fails" 2>/dev/null)" ""

# At home, no open port: quiet twice, red with the fix on the 3rd, then quiet again.
setup; run; check "noport 1: rc" "$rc" 0; check "noport 1: quiet" "$out" ""
run; check "noport 2: rc" "$rc" 0
run; check "noport 3: rc" "$rc" 1
case "$out" in *"turn on Wireless debugging"*) pass=$((pass+1)) ;; *) failn=$((failn+1)); echo "FAIL: noport 3 output: $out" ;; esac
run; check "noport 4: alerted once" "$rc" 0; check "noport 4: quiet" "$out" ""
# ... and a reconnect clears it, so the next outage alerts again.
echo 40001 >"$T/open"; run; check "recover: rc" "$rc" 0
check "recover: cleared" "$(ls "$T/state")" ""

# Away from home (relayed over LTE): never red.
setup; echo "DERP(den)" >"$T/ping"; for _ in 1 2 3 4; do run; check "away: rc" "$rc" 0; done

# Trust gone: unauthorized -> disconnected, and the alert names the re-pair.
setup; echo 40003 >"$T/open"; echo unauthorized >"$T/connect_state"
run; run; run; check "unauth: rc" "$rc" 1
case "$out" in *"adb pair"*) pass=$((pass+1)) ;; *) failn=$((failn+1)); echo "FAIL: unauth output: $out" ;; esac
check "unauth: disconnected" "$(cat "$T/devices")" ""

echo "$pass passed, $failn failed"
[ "$failn" = 0 ] && echo PASS || { echo FAIL; exit 1; }
