#!/usr/bin/env bash
# Every open PR across the bmbell23 repos, for the Dashboard's Open PRs section
# (docker#80, Dashboard#44). Third step of dagu/dags/deploy-reconciler.yaml, every 2 min.
# The Dashboard has no GitHub credentials (13 repos are private), so the host writes it.
#
# One GraphQL search call. Output, written atomically (tmp + mv):
#   {"updated": iso, "prs": [{repo, number, title, url, author, branch, created_at, is_draft}]}
# newest first. If GitHub can't be reached or answers oddly, the old file stays, so
# "updated" goes stale and the Dashboard says so. Exits 0 either way: staleness is the
# alert, not a red DAG every 2 minutes.
#
#   open-prs.sh [--stdout]
set -uo pipefail
OUT="${RECONCILE_OUT:-/home/brandon/projects/docker/logs/deploy}/open_prs.json"
OWNER="${OPEN_PRS_OWNER:-bmbell23}"

raw=$(timeout 60 gh api graphql -f q="owner:$OWNER is:pr is:open archived:false" -f query='
query($q: String!) {
  search(query: $q, type: ISSUE, first: 100) {
    issueCount
    nodes { ... on PullRequest {
      number title url isDraft createdAt headRefName
      author { login } repository { name }
    } }
  }
}' 2>&1) || { echo "open-prs: gh failed, kept the old file: ${raw:0:200}"; exit 0; }

json=$(jq -e --arg now "$(date -Iseconds)" '
  if (.data.search.issueCount // -1) > 100 then error("more than 100 open PRs; paginate") else . end
  | {updated: $now, prs: [.data.search.nodes[] | select(.number) | {
      repo: .repository.name, number, title, url, author: (.author.login // "ghost"),
      branch: .headRefName, created_at: .createdAt, is_draft: .isDraft}]
     | sort_by(.created_at) | reverse}' <<<"$raw" 2>&1) \
    || { echo "open-prs: unexpected answer, kept the old file: ${json:0:200}"; exit 0; }

[ "${1:-}" = --stdout ] && { echo "$json"; exit 0; }
mkdir -p "$(dirname "$OUT")"
tmp=$(mktemp "$OUT.XXXXXX") && printf '%s\n' "$json" > "$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$OUT" \
    || { rm -f "${tmp:-}"; echo "open-prs: couldn't write $OUT"; exit 1; }
echo "open-prs: $(jq '.prs | length' <<<"$json") open PR(s) -> $OUT"
