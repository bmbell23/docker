#!/bin/bash

# Database Backup Script
# Backs up all important Docker databases to NAS.
# Immich is not here: it writes its own nightly dumps to
# /mnt/boston/media/pictures/immich-storage/backups/.
#
# Exits non-zero if any backup fails. Old backups of a service are pruned only
# after that service's new backup succeeded, and the newest KEEP_MIN are always kept.

set -o pipefail

BACKUP_DIR="/mnt/boston/docker-backups"
TRILIUM_DOCS_DIR="/mnt/boston/documents/trilium-backups"
TRILIUM_DATA_DIR="/home/brandon/projects/docker/trilium/data"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30
KEEP_MIN=7
MIN_BYTES=1024  # anything smaller is a failed dump (an empty .gz is 20 bytes)

mkdir -p "$BACKUP_DIR" "$TRILIUM_DOCS_DIR"

FAILED=0

# ok <file> — true if the backup file exists and is not suspiciously small
ok() {
    [ -f "$1" ] && [ "$(stat -c %s "$1")" -ge "$MIN_BYTES" ]
}

# prune <dir> <glob> — delete files older than RETENTION_DAYS, keeping the newest KEEP_MIN
prune() {
    ls -1t "$1"/$2 2>/dev/null | tail -n +$((KEEP_MIN + 1)) | while read -r f; do
        if [ -n "$(find "$f" -mtime +$RETENTION_DAYS)" ]; then
            rm -f "$f" && echo "  pruned $(basename "$f")"
        fi
    done
}

# report <name> <file> <dir> <glob>
report() {
    if ok "$2"; then
        echo "✓ $1 backup successful ($(stat -c %s "$2") bytes)"
        prune "$3" "$4"
    else
        echo "✗ $1 backup failed"
        FAILED=1
    fi
}

echo "Starting database backups at $(date)"

# RomM MariaDB Backup (credentials come from the container's own env)
echo "Backing up RomM database..."
OUT="$BACKUP_DIR/romm_${DATE}.sql.gz"
docker exec romm-db sh -c 'mariadb-dump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' | gzip > "$OUT" || rm -f "$OUT"
report RomM "$OUT" "$BACKUP_DIR" 'romm_*.sql.gz'

# Jellyfin SQLite Backup
echo "Backing up Jellyfin database..."
# Find the actual Jellyfin container name (it changes with docker-compose)
JELLYFIN_CONTAINER=$(docker ps --filter "ancestor=jellyfin/jellyfin:latest" --format "{{.Names}}" | head -1)
OUT="$BACKUP_DIR/jellyfin_${DATE}.db"
if [ -z "$JELLYFIN_CONTAINER" ]; then
    echo "  Jellyfin container not found"
else
    docker exec "$JELLYFIN_CONTAINER" cp /config/data/jellyfin.db /config/data/jellyfin_backup.db &&
        docker cp "$JELLYFIN_CONTAINER":/config/data/jellyfin_backup.db "$OUT"
    docker exec "$JELLYFIN_CONTAINER" rm -f /config/data/jellyfin_backup.db
fi
report Jellyfin "$OUT" "$BACKUP_DIR" 'jellyfin_*.db'

# Trilium Notes Backup (SQLite in WAL mode: .backup gives a consistent copy, cp would not).
# .backup goes to local disk first: SQLite can't lock files on the NAS's SMB mount.
echo "Backing up Trilium database..."
OUT="$TRILIUM_DOCS_DIR/trilium_${DATE}.db.gz"
TMP=$(mktemp --suffix=.db)
if sqlite3 "$TRILIUM_DATA_DIR/document.db" ".backup '$TMP'"; then
    gzip -c "$TMP" > "$OUT" || rm -f "$OUT"
fi
rm -f "$TMP"
report Trilium "$OUT" "$TRILIUM_DOCS_DIR" 'trilium_*.db.gz'

echo "Backup completed at $(date)"
echo "Backups stored in: $BACKUP_DIR"
echo "Trilium backups also in: $TRILIUM_DOCS_DIR"

exit $FAILED
