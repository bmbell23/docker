#!/usr/bin/env bash
# Keep the host's adb connected to Brandon's Fold, for ws-scrcpy (docker#173, docker#171).
# Wireless debugging moves to a new port on every reboot or toggle. The phone keeps
# trusting dockerhost's adb key across that, so a reconnect needs only the new port, and
# a scan finds it: no pairing code. The dagu DAG phone-adb-reconnect runs this every
# 2 minutes; `phone reconnect` (dotfiles) runs it by hand.
#   phone-adb-reconnect.sh
# Prints nothing when there was nothing to do (so the idle poller stays quiet), one line
# when it reconnected. Exits 1 once per outage, after FAIL_AFTER failed runs in a row
# while the phone is on the home LAN; every other failure exits 0 quietly. Away from
# home (LTE) Wireless debugging is off by design, so no alert.

set -uo pipefail

PHONE="${PHONE_IP:-100.78.213.32}"
HOME_LAN="${HOME_LAN_PREFIX:-10.0.0.}"
PORTS="${PHONE_PORTS:-30000 49999}"
FAIL_AFTER="${FAIL_AFTER:-3}"
STATE="${PHONE_ADB_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/phone-adb}"
mkdir -p "$STATE"

state_of() {   # the adb state of any serial for the phone (device/offline/unauthorized), or empty
    adb devices | awk -v p="$PHONE:" 'index($1, p) == 1 { print $1, $2 }'
}

ok() {         # connected: clear the failure count; say so only if we did something
    rm -f "$STATE/fails" "$STATE/alerted"
    [ -n "${1:-}" ] && echo "$1"
    exit 0
}

fail() {       # fail <reason> <fix>: count it, and alert once the count reaches FAIL_AFTER
    local n; n=$(( $(cat "$STATE/fails" 2>/dev/null || echo 0) + 1 ))
    echo "$n" >"$STATE/fails"
    if [ "$at_home" = 1 ] && [ "$n" -ge "$FAIL_AFTER" ] && [ ! -e "$STATE/alerted" ]; then
        touch "$STATE/alerted"
        echo "Fold not connected to adb ($n runs in a row): $1"
        echo "Fix: $2"
        exit 1
    fi
    exit 0
}

cur=$(state_of)
case "$cur" in *" device"*) ok ;; esac

# Reachable at all? Offline or out of Tailscale: nothing to do, nothing to say.
pong=$(tailscale ping -c 1 --timeout 3s "$PHONE" 2>&1) || exit 0
at_home=0; case "$pong" in *"via $HOME_LAN"*) at_home=1 ;; esac

# A serial left over from the old port shows as offline; drop it so ws-scrcpy sees one phone.
for serial in $(echo "$cur" | awk '$2 != "device" { print $1 }'); do adb disconnect "$serial" >/dev/null 2>&1; done

read -r lo hi <<<"$PORTS"
open=$(seq "$lo" "$hi" | xargs -P 200 -I{} sh -c 'nc -z -w1 "$0" {} 2>/dev/null && echo {}' "$PHONE" | sort -n)
[ -n "$open" ] || fail "no open port in $lo-$hi" \
    "turn on Wireless debugging (Settings → System → Developer options → Wireless debugging)"

for port in $open; do
    adb connect "$PHONE:$port" >/dev/null 2>&1
    for _ in 1 2 3 4 5; do
        case "$(state_of)" in
        *" device"*) ok "reconnected: $PHONE:$port" ;;
        *unauthorized*)
            adb disconnect "$PHONE:$port" >/dev/null 2>&1
            fail "the phone no longer trusts dockerhost (unauthorized on :$port)" \
                "Wireless debugging → Pair device with pairing code, then on dockerhost: adb pair $PHONE:<pair-port> <code>" ;;
        esac
        sleep 1
    done
    adb disconnect "$PHONE:$port" >/dev/null 2>&1
done
fail "adb connect failed on every open port ($(echo $open))" "check Wireless debugging is on, then run phone-adb-reconnect.sh by hand"
