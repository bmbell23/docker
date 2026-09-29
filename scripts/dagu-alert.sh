#!/bin/bash
# Tell #infra when a Dagu job goes red, and again when it goes green (docker#12).
# Called from a DAG's handler_on over ssh:
#   dagu-alert.sh failed <dag> <run-id>   on failure
#   dagu-alert.sh ok     <dag> <run-id>   on success
# Alerts on the change only: a job that stays red posts once, not every run.
# Posts as Dakota through agent-bus bin/say, which keeps the bot token out of here.
# ALERT_TEST=1 prefixes [test] and drops the @brandon ping.

set -uo pipefail

status="$1"
dag="$2"
run="${3:-}"

SAY=/home/brandon/projects/agent-bus/bin/say
CHANNEL="${ALERT_CHANNEL:-#infra}"
LOGS=/home/brandon/projects/docker/dagu/logs
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dagu-alerts"
URL="http://100.69.184.113:8014/dags/$dag"

mkdir -p "$STATE_DIR"
state_file="$STATE_DIR/$dag"
prev=$(cat "$state_file" 2>/dev/null || echo ok)

who="@brandon "
prefix=""
if [ "${ALERT_TEST:-0}" = "1" ]; then
    who=""
    prefix="[test] "
fi

# Last lines of this run's step output, minus the host's tput noise.
log_tail() {
    local dir
    dir=$(ls -d "$LOGS/$dag"/dag-run_*"$run"* 2>/dev/null | head -n 1)
    [ -n "$run" ] && [ -n "$dir" ] || return 0
    find "$dir" -type f \( -name '*.out' -o -name '*.err' \) -print0 2>/dev/null |
        xargs -0 -r cat 2>/dev/null | grep -v 'tput: No value for \$TERM' | tail -n 8
}

case "$status" in
failed)
    echo failed > "$state_file"
    if [ "$prev" = failed ]; then
        echo "$dag already red; not re-alerting"
        exit 0
    fi
    msg="${prefix}${who}Backup job \`$dag\` failed (run \`$run\`). I won't repeat this while it stays red; you'll hear when it's green again. $URL"
    tail=$(log_tail)
    if [ -n "$tail" ]; then
        msg="$msg
\`\`\`
$tail
\`\`\`"
    fi
    ;;
ok)
    echo ok > "$state_file"
    if [ "$prev" != failed ]; then
        exit 0
    fi
    msg="${prefix}Backup job \`$dag\` is green again (run \`$run\`)."
    ;;
*)
    echo "usage: $0 failed|ok <dag> [run-id]" >&2
    exit 2
    ;;
esac

printf '%s\n' "$msg" | "$SAY" dakota "$CHANNEL" -
