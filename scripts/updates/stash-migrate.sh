#!/usr/bin/env bash
# post hook for stash in dagu/update-stacks.yaml (docker#37). After a new image, Stash
# may sit at NEEDS_MIGRATION and serve nothing (docker#25). If so, run its migrate
# with a backup next to the database (the path the Stash UI itself proposes:
# <databasePath>.<old schema>.<timestamp>), then wait for OK. Exit 0 if Stash is OK.
set -uo pipefail
URL="${STASH_URL:-http://localhost:9999/graphql}"
gql() { curl -s -m 30 -X POST "$URL" -H 'Content-Type: application/json' -d "$1"; }
status() { gql '{"query":"{ systemStatus { status databasePath databaseSchema appSchema } }"}'; }

for _ in $(seq 1 30); do s=$(status) && [ -n "$s" ] && break; sleep 5; done
st=$(jq -r '.data.systemStatus.status // empty' <<<"${s:-}")
case "$st" in
    OK) echo "stash: no migration needed"; exit 0 ;;
    NEEDS_MIGRATION) ;;
    *) echo "stash: unexpected status '${st:-no answer}'"; exit 1 ;;
esac

db=$(jq -r .data.systemStatus.databasePath <<<"$s")
from=$(jq -r .data.systemStatus.databaseSchema <<<"$s"); to=$(jq -r .data.systemStatus.appSchema <<<"$s")
backup="$db.$from.$(date +%Y%m%d_%H%M%S)"
echo "stash: migrating schema $from -> $to, backup $backup"
r=$(gql "$(jq -nc --arg b "$backup" '{query:"mutation($b:String!){ migrate(input:{backupPath:$b}) }",variables:{b:$b}}')")
echo "$r"
jq -e '.data.migrate' <<<"$r" >/dev/null || { echo "stash: migrate was refused"; exit 1; }

for _ in $(seq 1 60); do
    sleep 10
    st=$(status | jq -r '.data.systemStatus.status // empty')
    [ "$st" = OK ] && { echo "stash: migrated to schema $to"; exit 0; }
done
echo "stash: still '${st:-no answer}' 10 min after migrate"; exit 1
