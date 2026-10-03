#!/bin/bash
# Post every Dagu run's result to #dagu as @rabbot (docker#12, docker#57).
# Called from a DAG's handler_on over ssh:
#   dagu-alert.sh failed <dag> <run-id>          on failure
#   dagu-alert.sh ok     <dag> <run-id> [idle]   on success
# Every failure posts with its log tail; @brandon is pinged only when a job turns red.
# Every success posts a ✅, except "idle" pollers (every few minutes), which post only
# when the run printed something, i.e. actually did work. Otherwise #dagu gets ~900
# "nothing new" posts a day.
# Each DAG gets one thread per day (docker#94): the day's first post is a root naming the
# job and date, every run that day replies under it. Every reply links to its run in Dagu.
# Posts through agent-bus bin/say, which keeps the token out of here; it replies in a
# thread when given SAY_ROOT=<post id> and prints the new post's id on stdout.
# ALERT_TEST=1 prefixes [test] and drops the @brandon ping.

set -uo pipefail

status="$1"
dag="$2"
run="${3:-}"
mode="${4:-}"

SAY="${ALERT_SAY:-/home/brandon/projects/agent-bus/bin/say}"
BOT="${ALERT_BOT:-rabbot}"
CHANNEL="${ALERT_CHANNEL:-#dagu}"
LOGS=/home/brandon/projects/docker/dagu/logs
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dagu-alerts"
DAGU="http://100.69.184.113:8014"
URL="$DAGU/dag-runs/$dag/$run"
TODAY=$(date +%F)

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
        msg="${prefix}🔴 \`$dag\` failed again ([run \`$run\`]($URL)), still red."
    else
        msg="${prefix}${who}🔴 \`$dag\` failed ([run \`$run\`]($URL))."
    fi
    msg="$msg$(fence "$(log_tail 8)")"
    ;;
ok)
    echo ok > "$state_file"
    tail=$(log_tail 4)
    if [ "$prev" = failed ]; then
        msg="${prefix}✅ \`$dag\` is green again ([run \`$run\`]($URL))."
    elif [ "$mode" = idle ] && [ -z "$tail" ]; then
        exit 0
    else
        msg="${prefix}✅ \`$dag\` ok ([run \`$run\`]($URL))."
    fi
    msg="$msg$(fence "$tail")"
    ;;
*)
    echo "usage: $0 failed|ok <dag> [run-id] [idle]" >&2
    exit 2
    ;;
esac

# bin/say waits up to SAY_WAIT s for Mattermost; if it still fails, leave a trace (docker#35).
# post <root-id|""> <message>: prints the new post's id (empty if bin/say doesn't report one).
say_err=$(mktemp)
trap 'rm -f "$say_err"' EXIT
post() {
    local out
    out=$(printf '%s\n' "$2" | SAY_ROOT="$1" "$SAY" "$BOT" "$CHANNEL" - 2>"$say_err") || return 1
    printf '%s' "$out" | head -n 1 | tr -cd 'a-z0-9'
}

# Today's thread for this DAG: "<date> <root-id>", or "<date> flat" when bin/say can't
# thread, so we don't post a lone header on every run.
thread_file="$STATE_DIR/$dag.thread"
root=""
read -r day cached 2>/dev/null < "$thread_file" || true
[ "${day:-}" = "$TODAY" ] && root="${cached:-}"

new_thread() {
    local id
    id=$(post "" "${prefix}🧵 \`$dag\` · $TODAY · [all runs]($DAGU/dags/$dag)") || return 1
    root="${id:-flat}"
    echo "$TODAY $root" > "$thread_file"
}

deliver() {
    if [ -z "$root" ]; then
        new_thread || return 1
    fi
    if [ "$root" = flat ]; then
        post "" "$msg" >/dev/null
        return
    fi
    # A deleted root makes the reply fail; start a fresh thread once rather than lose the alert.
    post "$root" "$msg" >/dev/null && return
    new_thread || return 1
    post "${root#flat}" "$msg" >/dev/null
}

if ! deliver; then
    err=$(cat "$say_err")
    echo "ALERT NOT DELIVERED to $CHANNEL: ${err:-no reason given}" >&2
    logger -t dagu-alert "alert for $dag not delivered: ${err:-no reason given}" 2>/dev/null || true
    exit 1
fi
