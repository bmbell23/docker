#!/bin/bash
# Post every Dagu run's result to #dagu as @rabbot (docker#12, docker#57).
# Called from a DAG's handler_on over ssh:
#   dagu-alert.sh failed <dag> <run-id>          on failure
#   dagu-alert.sh ok     <dag> <run-id> [idle]   on success
# Every failure posts with its log tail; @brandon is pinged only when a job turns red.
# Every success posts a ✅, except "idle" pollers (every few minutes), which post only
# when the run printed something, i.e. actually did work. Otherwise #dagu gets ~900
# "nothing new" posts a day.
# Posts through agent-bus bin/say, which keeps the token out of here.
# ALERT_TEST=1 prefixes [test] and drops the @brandon ping.

set -uo pipefail

status="$1"
dag="$2"
run="${3:-}"
mode="${4:-}"

SAY=/home/brandon/projects/agent-bus/bin/say
BOT="${ALERT_BOT:-rabbot}"
CHANNEL="${ALERT_CHANNEL:-#dagu}"
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

# Last lines of this run's step output, minus the host's tput noise and the
# handlers' own (onSuccess/onFailure/onExit) logs.
log_tail() {
    local dir
    dir=$(ls -d "$LOGS/$dag"/dag-run_*"$run"* 2>/dev/null | head -n 1)
    [ -n "$run" ] && [ -n "$dir" ] || return 0
    find "$dir" -type f \( -name '*.out' -o -name '*.err' \) ! -name 'on[A-Z]*' -print0 2>/dev/null |
        xargs -0 -r cat 2>/dev/null | grep -v 'tput: No value for \$TERM' | grep . | tail -n "$1"
}

fence() {
    [ -n "$1" ] && printf '\n```\n%s\n```' "$1"
}

case "$status" in
failed)
    echo failed > "$state_file"
    if [ "$prev" = failed ]; then
        msg="${prefix}🔴 \`$dag\` failed again (run \`$run\`), still red. $URL"
    else
        msg="${prefix}${who}🔴 \`$dag\` failed (run \`$run\`). $URL"
    fi
    msg="$msg$(fence "$(log_tail 8)")"
    ;;
ok)
    echo ok > "$state_file"
    tail=$(log_tail 4)
    if [ "$prev" = failed ]; then
        msg="${prefix}✅ \`$dag\` is green again (run \`$run\`)."
    elif [ "$mode" = idle ] && [ -z "$tail" ]; then
        exit 0
    else
        msg="${prefix}✅ \`$dag\` ok (run \`$run\`)."
    fi
    msg="$msg$(fence "$tail")"
    ;;
*)
    echo "usage: $0 failed|ok <dag> [run-id] [idle]" >&2
    exit 2
    ;;
esac

# bin/say waits up to SAY_WAIT s for Mattermost; if it still fails, leave a trace (docker#35).
if ! err=$(printf '%s\n' "$msg" | "$SAY" "$BOT" "$CHANNEL" - 2>&1 >/dev/null); then
    echo "ALERT NOT DELIVERED to $CHANNEL: ${err:-no reason given}" >&2
    logger -t dagu-alert "alert for $dag not delivered: ${err:-no reason given}" 2>/dev/null || true
    exit 1
fi
