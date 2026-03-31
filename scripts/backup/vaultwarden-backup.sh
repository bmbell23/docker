#!/bin/bash
# Vaultwarden backup script
# Creates timestamped backups of Vaultwarden data with retention cleanup.

set -e

SERVICE_DIR="/home/brandon/projects/docker/vaultwarden"
DATA_DIR="$SERVICE_DIR/data"
BACKUP_ROOT="$SERVICE_DIR/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
ARCHIVE_PATH="$BACKUP_DIR/vaultwarden-data.tar.gz"
KEEP_DAYS=30

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

if [ ! -d "$DATA_DIR" ]; then
    log "ERROR: Data directory not found: $DATA_DIR"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

log "Starting Vaultwarden backup"
log "Service directory: $SERVICE_DIR"

# Ensure SQLite state is in a clean file on disk before archiving.
if docker ps --format '{{.Names}}' | grep -q '^vaultwarden$'; then
    if docker exec vaultwarden sh -c 'command -v sqlite3 >/dev/null 2>&1'; then
        log "Vaultwarden container detected; checkpointing SQLite WAL"
        docker exec vaultwarden sh -c 'sqlite3 /data/db.sqlite3 "PRAGMA wal_checkpoint(FULL);"' >/dev/null
    else
        log "Vaultwarden container detected; sqlite3 not found in container, skipping WAL checkpoint"
    fi
fi

tar -czf "$ARCHIVE_PATH" -C "$SERVICE_DIR" data

if [ ! -s "$ARCHIVE_PATH" ]; then
    log "ERROR: Backup archive was not created"
    exit 1
fi

tar -tzf "$ARCHIVE_PATH" >/dev/null

find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +$KEEP_DAYS -exec rm -rf {} \;

ARCHIVE_SIZE=$(du -sh "$ARCHIVE_PATH" | cut -f1)
log "Backup completed: $ARCHIVE_PATH ($ARCHIVE_SIZE)"
log "Retention: removed backups older than $KEEP_DAYS days"
