#!/bin/bash
# Second copy of boston's Tier 1 data onto the Allston USB drive (docker#14).
# Runs ON PROXMOX, streamed by Dagu: ssh proxmox 'bash -s' < this file.
# Replaces backup-script.sh's target /mnt/backups (sdc1, dead since 2026-05-30).
#
# Destination is the subfolder Brandon approved -- never /mnt/allston itself,
# which holds his own Documents/Downloads/Videos.
# No --delete until one full pass has landed (set BOSTON_COPY_DELETE=1 after),
# so an interrupted or re-run copy can never remove anything.

set -euo pipefail

DEST=/mnt/allston/boston-copy
SOURCES=(
    /mnt/boston/documents
    /mnt/boston/media/audiobooks
    /mnt/boston/media/books
    /mnt/boston/media/games
    /mnt/boston/media/music
    /mnt/boston/media/pictures
)

# mountpoint -q passes on a dead-but-mounted FUSE disk (that is how sdc hid for
# four months), so prove both ends are actually readable.
for d in /mnt/boston "$DEST"; do
    if ! timeout 10 ls "$d" >/dev/null 2>&1; then
        echo "FAILED: $d is not readable" >&2
        exit 1
    fi
done

opts=(-ah --stats)
[ "${BOSTON_COPY_DELETE:-0}" = "1" ] && opts+=(--delete)

exec 9>/tmp/boston-copy.lock
if ! flock -n 9; then
    echo "FAILED: another boston-copy rsync is still running" >&2
    exit 1
fi

echo "copying ${#SOURCES[@]} trees -> $DEST (delete=${BOSTON_COPY_DELETE:-0})"
rsync "${opts[@]}" "${SOURCES[@]}" "$DEST/"
echo "Backup completed: $(du -sh "$DEST" | cut -f1) in $DEST"
