#!/usr/bin/env bash
# dockerhost's side of taking pve01 down (docker#111): keep its downtime from paging
# Mongo and painting #dagu red, then prove it came back. pve01 itself (k3s VMs, PBS,
# restic) is Peter's, in bmbell23/proxmox; this touches only Dagu and Alertmanager here.
#
#   pve01-maintenance.sh start [--hours 4]   pve01 jobs idle? suspend every pve01-* DAG,
#                                            silence pve01 + k3s01-03 alerts, the K3s* rules
#                                            and the k3s services' Dashboard cards, record RAM
#   pve01-maintenance.sh end                 nodes back? RAM before/after, resume the DAGs,
#                                            run pve01-homelab-pull once, lift the silences
#   pve01-maintenance.sh status
#   pve01-maintenance.sh check               window overrun? Mongo nags (at most every
#                                            MAINT_NAG_HOURS, 6) and exit 1; else silent, 0.
#                                            Hourly from dagu/dags/maintenance-guard.yaml (docker#149)
#
# It says so in #infra: Mongo (bad news) at start, "we know, it's planned", so a quiet
# Mongo means hushed, not broken; Biscuit when it's back, or Mongo when it isn't.
# Exit codes: 0 done, 1 failed, 3 a pve01 job is still running (start: try again soon).
# Needs dagu/.drain.env (the same Dagu API credentials as dagu-drain.sh). Agents never read it.
# check doesn't: it reads only the state file and dagu/data/suspend/, so Dagu can run it.
# State: logs/maintenance/pve01.state (logs/ is gitignored).
set -uo pipefail

ROOT="${MAINT_ROOT:-/home/brandon/projects/docker}"
DAGU="${MAINT_DAGU:-http://localhost:8014/api/v1}"
PROM="${MAINT_PROM:-http://localhost:9090/api/v1}"
AM="${MAINT_AM:-http://localhost:9093/api/v2}"
ENVF="$ROOT/dagu/.drain.env"
STATE="$ROOT/logs/maintenance/pve01.state"
NAG_HOURS="${MAINT_NAG_HOURS:-6}"
SAY="${MAINT_SAY:-/home/brandon/projects/agent-bus/bin/say}"
CHANNEL="${MAINT_CHANNEL:-#infra}"
INSTANCES='pve01|k3s01|k3s02|k3s03'   # Prometheus instance labels behind pve01 (monitoring/prometheus/prometheus.yml)
HUSHED="$INSTANCES|k3s"               # + kube-state-metrics, scraped as instance=k3s (docker#139)
K3S_URLS='.*10\.0\.0\.201.*'          # k3s01's ingress: ServiceDown for these cards has instance=dockerhost (docker#137)
K3S_ALERTS='K3s.*'                    # monitoring/prometheus/rules/k3s.yml: all k3s-only; K3sIngressDown's instance is a URL (docker#139)

cmd="${1:-}"; shift || true
hours=4
while [ $# -gt 0 ]; do
    case "$1" in
    --hours) hours="$2"; shift ;;
    *) cmd=bad ;;
    esac
    shift
done
case "$cmd" in start|end|status|check) ;; *) echo "usage: $0 start [--hours 4] | end | status | check" >&2; exit 2 ;; esac

post() {   # post <bot> <message>: never fatal, but say so when it didn't land
    printf '%s\n' "$2" | "$SAY" "$1" "$CHANNEL" - >/dev/null || echo "(couldn't post to $CHANNEL as $1)"
}
die() { echo "FAILED: $*"; post mongo "🦖 **pve01 maintenance** ($cmd) failed: $*"; exit 1; }
gib() { awk -v b="$1" 'BEGIN { printf "%.1f GiB", b / 1073741824 }'; }

state() { grep -m1 "^$1=" "$STATE" 2>/dev/null | cut -d= -f2-; }

if [ "$cmd" = check ]; then   # docker#149: suspend flags don't expire like the silences do
    [ -f "$STATE" ] || exit 0
    started=$(state started)
    s_epoch=$(date -d "$started" +%s 2>/dev/null) || { echo "FAILED: unreadable started='$started' in $STATE"; exit 1; }
    planned=$(state hours); until=$(state until)
    if [ -z "$until" ]; then until=$(date -Iseconds -d "@$((s_epoch + ${planned:-12} * 3600))"); planned=${planned:-"unknown, assumed 12"}; fi   # pre-#149 state files
    now=$(date +%s); u_epoch=$(date -d "$until" +%s)
    [ "$now" -lt "$u_epoch" ] && { echo "inside the window until $until"; exit 0; }
    flags=$(find "$ROOT/dagu/data/suspend" -maxdepth 1 -name 'pve01-*.suspend' -printf '%f\n' 2>/dev/null | sed 's/\.suspend$//' | sort)
    n=$(printf '%s' "$flags" | grep -c .)
    over=$(( (now - u_epoch) / 3600 ))
    msg="pve01 maintenance still open since $(date -d "$started" '+%a %b %-d %H:%M') (planned ${planned} h, ${over} h over). $n Dagu job(s) suspended: $(printf '%s' "$flags" | paste -sd, | sed 's/,/, /g'). Backups wait until someone runs \`pve01-maintenance.sh end\`."
    echo "OVERDUE: $msg"
    nagged=$(state nagged)
    if [ -z "$nagged" ] || [ $((now - nagged)) -ge $((NAG_HOURS * 3600)) ]; then
        post mongo "🦖 **RAWR. $msg**"
        if grep -q '^nagged=' "$STATE"; then sed -i "s/^nagged=.*/nagged=$now/" "$STATE"; else echo "nagged=$now" >>"$STATE"; fi
    else
        echo "(Mongo already nagged $(( (now - nagged) / 60 )) min ago; next in under $NAG_HOURS h)"
    fi
    exit 1
fi

[ -r "$ENVF" ] || die "no $ENVF (see dagu/README.md, 'Recreating or updating Dagu')"
# shellcheck disable=SC1090
. "$ENVF"
auth=()
if [ -n "${DAGU_API_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer $DAGU_API_TOKEN")
elif [ -n "${DAGU_USER:-}" ]; then auth=(-u "$DAGU_USER:${DAGU_PASS:-}")
else die "$ENVF sets neither DAGU_API_TOKEN nor DAGU_USER"; fi

dags() { find "$ROOT/dagu/dags" -maxdepth 1 -name 'pve01-*.yaml' -printf '%f\n' | sed 's/\.yaml$//' | sort; }
suspended() { curl -s -m 10 "${auth[@]}" "$DAGU/dags/$1" | jq -r '.suspended' 2>/dev/null; }
set_suspend() {   # set_suspend <dag> true|false: 0 when Dagu reports it back
    curl -s -m 10 -o /dev/null -X POST "${auth[@]}" -H 'Content-Type: application/json' \
        -d "{\"suspend\": $2}" "$DAGU/dags/$1/suspend"
    [ "$(suspended "$1")" = "$2" ]
}
in_flight() { local d; for d in $(dags); do find "$ROOT/dagu/data/proc/$d" -name '*.proc' 2>/dev/null | grep -q . && echo "$d"; done; }   # as dagu-drain.sh
prom() { curl -s -m 10 "$PROM/query" --data-urlencode "query=$1" | jq -r '.data.result[] | "\(.metric.instance) \(.value[1])"' 2>/dev/null; }
memtotal() { prom 'node_memory_MemTotal_bytes{instance="pve01"}' | awk '{print $2}'; }
silence() {   # silence <matchers json> <from> <until>: prints the silence ID, or nothing
    jq -nc --argjson m "$1" --arg s "$2" --arg e "$3" \
        '{matchers: $m, startsAt: $s, endsAt: $e, createdBy: "pve01-maintenance.sh", comment: "pve01 maintenance (docker#111)"}' |
        curl -s -m 10 -X POST -H 'Content-Type: application/json' -d @- "$AM/silences" | jq -r '.silenceID // empty'
}

report() {
    local d
    echo "pve01 DAGs:"; for d in $(dags); do echo "  $d  suspended=$(suspended "$d")"; done
    echo "targets (up):"; prom "up{instance=~\"$INSTANCES\"}" | sed 's/^/  /'
    echo "pve01 RAM: $(m=$(memtotal); [ -n "$m" ] && gib "$m" || echo unknown)"
    [ -f "$STATE" ] && { echo "maintenance started $(state started), silences $(state silence) $(state silence_cards) $(state silence_k3s)"; } || echo "not in maintenance"
}

case "$cmd" in
status) report; exit 0 ;;

start)
    [ -f "$STATE" ] && die "already in maintenance since $(state started); run '$0 end' first"
    busy=$(in_flight | paste -sd' ')
    [ -n "$busy" ] && { echo "WAITING ON: $busy (running now; nothing changed). Try again in a few minutes."; exit 3; }
    mem=$(memtotal)
    mkdir -p "$(dirname "$STATE")"
    { echo "started=$(date -Iseconds)"; echo "hours=$hours"; echo "until=$(date -Iseconds -d "+$hours hours")"; echo "mem_before=$mem"; } >"$STATE"
    for d in $(dags); do
        set_suspend "$d" true || die "couldn't suspend $d (others may already be suspended: '$0 status', then '$0 end' to undo)"
        echo "suspended $d"
    done
    now=$(date -u +%FT%TZ); until=$(date -u -d "+$hours hours" +%FT%TZ)
    sid=$(silence "$(jq -nc --arg re "$HUSHED" '[{name: "instance", value: $re, isRegex: true, isEqual: true}]')" "$now" "$until")
    [ -n "$sid" ] || die "DAGs are suspended, but the Alertmanager silence failed: pve01 alerts will still fire"
    echo "silence=$sid" >>"$STATE"
    echo "silenced instance=~$HUSHED until $until ($sid)"
    # The Dashboard probes k3s01's services too (Rancher, ArgoCD, Dictionary...): ServiceDown, instance=dockerhost.
    cid=$(silence "$(jq -nc --arg re "$K3S_URLS" '[{name: "alertname", value: "ServiceDown", isRegex: false, isEqual: true},
                                                   {name: "url", value: $re, isRegex: true, isEqual: true}]')" "$now" "$until")
    [ -n "$cid" ] || die "pve01 alerts are silenced ($sid), but the ServiceDown silence for k3s01's cards failed: they will still page"
    echo "silence_cards=$cid" >>"$STATE"
    echo "silenced ServiceDown url=~$K3S_URLS until $until ($cid)"
    kid=$(silence "$(jq -nc --arg re "$K3S_ALERTS" '[{name: "alertname", value: $re, isRegex: true, isEqual: true}]')" "$now" "$until")
    [ -n "$kid" ] || die "pve01 alerts and cards are silenced ($sid $cid), but the K3s* silence failed: Rancher's warm-up will still page"
    echo "silence_k3s=$kid" >>"$STATE"
    echo "silenced alertname=~$K3S_ALERTS until $until ($kid)"
    echo "pve01 RAM now: $([ -n "$mem" ] && gib "$mem" || echo unknown)"
    echo "READY: dockerhost won't touch pve01. Peter's side next, then shut it down."
    post mongo "🦖🔧 *Mongo knows.* **pve01 is down for planned maintenance** until $(date -d "+$hours hours" '+%H:%M'). Alerts for \`pve01\`, \`k3s01-03\`, the k3s cluster and the k3s services' cards are hushed and the pve01 Dagu jobs are paused, so no RAWR from me about them until then. Still down after that, and I go loud."
    ;;

end)
    [ -f "$STATE" ] || echo "(no state file: resuming anyway)"
    problems=0
    down=$(prom "up{instance=~\"$INSTANCES\"} == 0" | awk '{print $1}' | paste -sd' ')
    up_n=$(prom "up{instance=~\"$INSTANCES\"} == 1" | wc -l)
    if [ -n "$down" ] || [ "$up_n" -lt 4 ]; then echo "NOT BACK: ${down:-fewer than 4 targets reporting} (up: $up_n/4)"; problems=1; fi
    before=$(state mem_before); after=$(memtotal)
    echo "pve01 RAM: $([ -n "$before" ] && gib "$before" || echo unknown) -> $([ -n "$after" ] && gib "$after" || echo unknown)"
    for d in $(dags); do
        set_suspend "$d" false || die "couldn't resume $d"
        echo "resumed $d"
    done
    curl -sf -m 10 -o /dev/null -X POST "${auth[@]}" -H 'Content-Type: application/json' -d '{}' "$DAGU/dags/pve01-homelab-pull/start" \
        && echo "started pve01-homelab-pull (it posts in #dagu only if it goes red)"
    for sid in $(state silence) $(state silence_cards) $(state silence_k3s); do
        if [ "$problems" = 0 ]; then
            curl -s -m 10 -o /dev/null -X DELETE "$AM/silence/$sid" && echo "silence $sid lifted"
        else
            echo "silence $sid LEFT ON (expires by itself); rerun '$0 end' once everything is up"
        fi
    done
    ram="$([ -n "$before" ] && gib "$before" || echo '?') → $([ -n "$after" ] && gib "$after" || echo '?')"
    if [ "$problems" = 0 ]; then
        rm -f "$STATE"; echo "DONE: pve01 back, jobs resumed."
        post biscuit "**pve01 is back** from maintenance. pve01 + k3s01-03 up, RAM $ram, Dagu jobs resumed, alerts live again."
    else
        post mongo "🦖 **pve01 maintenance isn't over:** not back: ${down:-some targets missing} ($up_n/4 up). Alerts stay hushed until the silence runs out; rerun \`pve01-maintenance.sh end\` once it's up."
    fi
    exit "$problems"
    ;;
esac
