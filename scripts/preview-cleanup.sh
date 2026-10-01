#!/usr/bin/env bash
# Remove PR preview containers once their PR is merged or closed (docker#49), then
# reclaim build leftovers. Second step of dagu/dags/deploy-reconciler.yaml, every 2 min.
#
# A preview (agent-bus README, "Preview containers"): compose project and container
# named <project>_pr<N>, labelled dashboard.preview.project=<card key> and
# dashboard.preview.pr=<N>. Scope guard: a container is touched only if it has both
# labels, its name is <something>_pr<N> with the same N, and its compose project is
# that same name. Nothing else, ever: no prod container, no volume.
#
# Repo: the dashboard.preview.repo label (owner/name) if set, else the `repo` of the
# Dashboard card whose key, name or preview_names matches (Dashboard/static/services.json).
# MERGED or CLOSED: remove the project's containers and networks, plus images built
# for the preview (<project>_pr<N>-*); shared images like the prod one stay. OPEN:
# left alone, running or stopped. Can't resolve: touched nothing, alerted once.
#
# Then, only if something was removed or deployed since the last time:
# dangling images and build cache older than 24 h. Never `system prune -a`.
#
#   preview-cleanup.sh [--dry-run]
set -uo pipefail

OUT="${RECONCILE_OUT:-/home/brandon/projects/docker/logs/deploy}"
SERVICES="${PREVIEW_SERVICES:-/home/brandon/projects/Dashboard/static/services.json}"
SAY="${RECONCILE_SAY:-/home/brandon/projects/agent-bus/bin/say}"
CHANNEL="${RECONCILE_CHANNEL:-#infra}"
dry=0; [ "${1:-}" = --dry-run ] && dry=1

mkdir -p "$OUT"
exec 9>"$OUT/.preview-lock"
flock -n 9 || { echo "another preview cleanup is running"; exit 0; }

post() {
    if [ "$dry" = 1 ]; then echo "[dry-run] would post: $1"; return 0; fi
    printf '%s\n' "$1" | "$SAY" biscuit "$CHANNEL" - \
        || { echo "ALERT NOT DELIVERED: $1" >&2; logger -t preview-cleanup "ALERT NOT DELIVERED: $1"; }
}
alert_once() {   # alert_once <container> <reason>: once per container and reason
    local f="$OUT/.preview-alerted-$1"
    [ "$(cat "$f" 2>/dev/null)" = "$2" ] && return 0
    post "@brandon preview \`$1\`: $2. Left it alone."
    [ "$dry" = 1 ] || echo "$2" > "$f"
}
run() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

repo_for() {   # repo_for <card key>: owner/name from the Dashboard's services.json
    python3 - "$SERVICES" "$1" <<'EOF' 2>/dev/null
import json, sys
key = sys.argv[2].lower()
for s in json.load(open(sys.argv[1])).get("services", []):
    names = {str(s.get("key", "")).lower(), str(s.get("name", "")).lower()}
    names |= {str(n).lower() for n in (s.get("preview_names") or [])}
    if key in names and s.get("repo"):
        print(s["repo"]); break
EOF
}

removed=0
while IFS='|' read -r name project pr repo cproj; do   # not tabs: read merges empty tab fields
    [ -n "$name" ] || continue
    if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]*_pr([0-9]+)$ ]] || [ "${BASH_REMATCH[1]}" != "$pr" ] || [ "$cproj" != "$name" ]; then
        alert_once "$name" "labelled as a preview but isn't named <project>_pr<N> with matching labels"; continue
    fi
    [ -n "$repo" ] || repo=$(repo_for "$project")
    [ -n "$repo" ] || { alert_once "$name" "no repo for card \`$project\` (set label dashboard.preview.repo=owner/name)"; continue; }
    state=$(gh pr view "$pr" -R "$repo" --json state -q .state 2>/dev/null) \
        || { alert_once "$name" "couldn't look up $repo#$pr on GitHub"; continue; }
    [ "$state" = MERGED ] || [ "$state" = CLOSED ] || continue
    rm -f "$OUT/.preview-alerted-$name"

    # Everything in that compose project (a preview may have its own db), then its networks
    # and only the images built for it. No -v: volumes stay.
    mapfile -t ids < <(docker ps -aq --filter "label=com.docker.compose.project=$name")
    mapfile -t imgs < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^${name}[-_]" || true)
    mapfile -t nets < <(docker network ls -q --filter "label=com.docker.compose.project=$name")
    [ ${#ids[@]} -gt 0 ] && run docker rm -f "${ids[@]}" >/dev/null
    [ ${#nets[@]} -gt 0 ] && { run docker network rm "${nets[@]}" >/dev/null || true; }
    [ ${#imgs[@]} -gt 0 ] && { run docker image rm "${imgs[@]}" >/dev/null || true; }
    echo "removed $name (${repo#*/}#$pr ${state,,}; ${#ids[@]} container(s), ${#imgs[@]} image(s))"
    post "Removed preview \`$name\` (${repo#*/}#$pr ${state,,})."
    removed=1
done < <(docker ps -a --filter label=dashboard.preview.project --filter label=dashboard.preview.pr \
           --format '{{.Names}}|{{.Label "dashboard.preview.project"}}|{{.Label "dashboard.preview.pr"}}|{{.Label "dashboard.preview.repo"}}|{{.Label "com.docker.compose.project"}}')

# Build leftovers, only after something changed: a removal here or a deploy log newer than the last prune.
stamp="$OUT/.last-prune"
if [ "$removed" = 1 ] || [ -n "$(find "$OUT" -maxdepth 1 -name '*.log' -newer "$stamp" 2>/dev/null | head -1)" ] || [ ! -e "$stamp" ]; then
    run docker image prune -f | tail -1
    run docker builder prune -f --filter until=24h | tail -1
    [ "$dry" = 1 ] || touch "$stamp"
fi
