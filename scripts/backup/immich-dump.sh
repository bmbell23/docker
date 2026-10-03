#!/bin/bash
# Fresh full dump of immich-db, verified, before container-updates recreates Immich (docker#26).
# A reverted image doesn't undo the DB migrations a new one already ran; this dump does.
# Kept next to Immich's own nightly dumps; the newest KEEP are kept.
set -uo pipefail
DIR=/mnt/boston/media/pictures/immich-storage/backups
KEEP=3
D="$DIR/pre-update-$(date +%Y%m%d-%H%M).sql.gz"

docker exec immich-db sh -c 'pg_dumpall -U "$POSTGRES_USER" --clean --if-exists' | gzip > "$D.tmp"
st=("${PIPESTATUS[@]}")
if [ "${st[0]}" = 0 ] && [ "${st[1]}" = 0 ] && zcat "$D.tmp" | tail -5 | grep -q 'PostgreSQL database cluster dump complete'; then
    mv "$D.tmp" "$D"
    echo "immich dump ok: $D ($(stat -c %s "$D") bytes)"
else
    rm -f "$D.tmp"
    echo "immich dump FAILED (pipestatus ${st[*]})" >&2
    exit 1
fi
ls -1t "$DIR"/pre-update-*.sql.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f
