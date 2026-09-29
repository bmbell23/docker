#!/bin/bash
# Copy boston's documents + pictures onto the "Blank" WD Passport, /mnt/external
# (docker#16). Runs ON PROXMOX, streamed by Dagu: ssh proxmox 'bash -s' < this file.
# Replaces backup-external.sh (pictures+videos, cron, last success 2026-05-26).
#
# Scope per the drive map: documents + media/pictures. The drive's older trees
# (videos, audiobooks, books, games from 2026-03-30) are left alone.
# No --delete until one full pass has landed (set EXTERNAL_COPY_DELETE=1 after).

set -euo pipefail

ROOT=/mnt/external
# Carried over from backup-external.sh: one Immich thumbnail folder it skipped.
PICTURES_EXCLUDE="${PICTURES_EXCLUDE:-thumbs/defc20ec-b70a-49b2-9938-70a4831be653/b4/4c/}"

# mountpoint -q passes on a dead-but-mounted FUSE disk, so prove both ends are readable.
for d in /mnt/boston "$ROOT"; do
    if ! timeout 10 ls "$d" >/dev/null 2>&1; then
        echo "FAILED: $d is not readable (drive unplugged or dead?)" >&2
        exit 1
    fi
done

opts=(-ah --stats)
[ "${EXTERNAL_COPY_DELETE:-0}" = "1" ] && opts+=(--delete)

exec 9>/tmp/external-copy.lock
if ! flock -n 9; then
    echo "FAILED: another external-copy rsync is still running" >&2
    exit 1
fi

echo "documents -> $ROOT/documents (delete=${EXTERNAL_COPY_DELETE:-0})"
rsync "${opts[@]}" /mnt/boston/documents/ "$ROOT/documents/"
echo "pictures -> $ROOT/media/pictures"
rsync "${opts[@]}" --exclude="$PICTURES_EXCLUDE" /mnt/boston/media/pictures/ "$ROOT/media/pictures/"
echo "Backup completed: $(df -h "$ROOT" | awk 'NR==2 {print $3" used, "$4" free"}') on $ROOT"
