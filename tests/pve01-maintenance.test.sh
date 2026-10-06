#!/usr/bin/env bash
# pve01-maintenance.sh against a fake curl (docker#139): start must silence every alert
# that pve01's downtime can raise, and end must lift every silence start made.
# Run: tests/pve01-maintenance.test.sh   (no network, no Dagu/Alertmanager needed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/root/dagu/dags" "$T/bin" "$T/am"
touch "$T/root/dagu/dags/pve01-homelab-pull.yaml"
echo 'DAGU_USER=x' >"$T/root/dagu/.drain.env"

# Fake curl: Dagu suspend state in files, Prometheus says all 4 targets up (none down),,
# Alertmanager keeps each POSTed silence as $T/am/<id>.json and logs DELETEs.
cat >"$T/bin/curl" <<'FAKE'
#!/usr/bin/env bash
method=GET; data=; url=; query=
while [ $# -gt 0 ]; do
    case "$1" in
    -X) method="$2"; shift ;;
    -d) data="$2"; shift ;;
    --data-urlencode) query="$2"; shift ;;
    -H|-u|-m|-o) shift ;;
    http*) url="$1" ;;
    esac
    shift
done
[ "$data" = @- ] && data=$(cat)
case "$url" in
*/silences) n=$(ls "$FAKE_AM" | wc -l); printf '%s' "$data" >"$FAKE_AM/s$n.json"; echo "{\"silenceID\":\"s$n\"}" ;;
*/silence/*) echo "${url##*/}" >>"$FAKE_AM/deleted" ;;
*/suspend) echo "$data" | jq -r .suspend >"$FAKE_AM/suspended" ;;
*/dags/*/start) ;;
*/dags/*) echo "{\"suspended\": $(cat "$FAKE_AM/suspended" 2>/dev/null || echo false)}" ;;
*/query) case "$query" in *'== 0'*) echo '{"data":{"result":[]}}'; exit 0 ;; esac
    echo '{"data":{"result":[{"metric":{"instance":"pve01"},"value":[0,"1"]},{"metric":{"instance":"k3s01"},"value":[0,"1"]},{"metric":{"instance":"k3s02"},"value":[0,"1"]},{"metric":{"instance":"k3s03"},"value":[0,"1"]}]}}' ;;
esac
FAKE
chmod +x "$T/bin/curl"
mkdir -p "$T/am-state"
export PATH="$T/bin:$PATH" FAKE_AM="$T/am-state" MAINT_ROOT="$T/root" MAINT_SAY=true

fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

out=$("$HERE/scripts/maintenance/pve01-maintenance.sh" start --hours 1); rc=$?
check "start exits 0" '[ $rc = 0 ]' || echo "$out"

# Does some silence match this alert's labels? (regex matchers are anchored, like Alertmanager.)
silenced() {   # silenced '<labels json>'
    cat "$FAKE_AM"/s*.json | jq -se --argjson l "$1" '
        any(.[]; all(.matchers[]; . as $m | ($l[$m.name] // "") as $v |
            if $m.isRegex then ($v | test("^(" + $m.value + ")$")) else $v == $m.value end))' >/dev/null
}
check "K3sIngressDown for Rancher (instance is the URL)" \
    "silenced '{\"alertname\":\"K3sIngressDown\",\"job\":\"k3s-ingress\",\"instance\":\"https://rancher.10.0.0.201.sslip.io\"}'"
check "K3sNodeMetricsMissing (absent(): no instance)"  "silenced '{\"alertname\":\"K3sNodeMetricsMissing\"}'"
check "K3sNodeNotReady"                                "silenced '{\"alertname\":\"K3sNodeNotReady\",\"instance\":\"k3s\",\"node\":\"k3s02\"}'"
check "TargetDown for kube-state-metrics (instance=k3s)" "silenced '{\"alertname\":\"TargetDown\",\"instance\":\"k3s\"}'"
check "TargetDown k3s01"                               "silenced '{\"alertname\":\"TargetDown\",\"instance\":\"k3s01\"}'"
check "VMStopped on pve01"                             "silenced '{\"alertname\":\"VMStopped\",\"instance\":\"pve01\"}'"
check "ServiceDown for Rancher's Dashboard card" \
    "silenced '{\"alertname\":\"ServiceDown\",\"instance\":\"dockerhost\",\"url\":\"https://rancher.10.0.0.201.sslip.io\"}'"
check "NOT: ServiceDown for a dockerhost app"          "! silenced '{\"alertname\":\"ServiceDown\",\"instance\":\"dockerhost\",\"url\":\"http://100.69.184.113:8003\"}'"
check "NOT: TargetDown for dockerhost"                 "! silenced '{\"alertname\":\"TargetDown\",\"instance\":\"dockerhost\"}'"
check "NOT: a k3s-looking instance name"               "! silenced '{\"alertname\":\"TargetDown\",\"instance\":\"k3s01x\"}'"

made=$(ls "$FAKE_AM"/s*.json | wc -l)
out=$("$HERE/scripts/maintenance/pve01-maintenance.sh" end); rc=$?
check "end exits 0" '[ $rc = 0 ]' || echo "$out"
check "end lifts all $made silences" '[ "$(sort -u "$FAKE_AM/deleted" | wc -l)" = "$made" ]'
check "end clears the state file" '[ ! -f "$T/root/logs/maintenance/pve01.state" ]'

[ $fail = 0 ] && echo "PASS" || echo "FAILED"
exit $fail
