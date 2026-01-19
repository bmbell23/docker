#!/bin/bash
# Immich Daily Backup Script
# Automatically backs up Immich database daily
# Add to crontab: 0 2 * * * /home/brandon/projects/docker/immich-daily-backup.sh

set -e

BACKUP_ROOT="/home/brandon/backups/immich-daily"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d)"
LOG_FILE="$BACKUP_ROOT/backup.log"
KEEP_DAYS=7  # Keep 7 days of backups

# Create backup directory
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_ROOT"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "Starting Immich Daily Backup"
log "========================================="

# Check if Immich is running
if ! docker ps | grep -q immich_postgres; then
    error "Immich PostgreSQL is not running!"
    exit 1
fi

# Backup PostgreSQL database
log "Backing up Immich database..."
if docker exec immich_postgres pg_dump -U postgres immich > "$BACKUP_DIR/immich.sql"; then
    gzip "$BACKUP_DIR/immich.sql"
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR/immich.sql.gz" | cut -f1)
    log "✓ Database backup complete: $BACKUP_DIR/immich.sql.gz ($BACKUP_SIZE)"
else
    error "Failed to backup Immich database"
    exit 1
fi

# Backup PostgreSQL data directory (for complete recovery)
log "Backing up PostgreSQL data directory..."
if sudo tar -czf "$BACKUP_DIR/postgres_data.tar.gz" -C /home/brandon/immich postgres 2>/dev/null; then
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR/postgres_data.tar.gz" | cut -f1)
    log "✓ PostgreSQL data backup complete: $BACKUP_DIR/postgres_data.tar.gz ($BACKUP_SIZE)"
else
    log "⚠ PostgreSQL data directory backup skipped (permission issue - SQL dump is sufficient)"
fi

# Clean up old backups
log "Cleaning up backups older than $KEEP_DAYS days..."
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mtime +$KEEP_DAYS -exec rm -rf {} \;
log "✓ Old backups cleaned up"

# Summary
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
BACKUP_COUNT=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" | wc -l)

log "========================================="
log "Backup Complete"
log "========================================="
log "Backup location: $BACKUP_DIR"
log "Backup size: $TOTAL_SIZE"
log "Total backups kept: $BACKUP_COUNT"
log ""

# Test backup integrity
log "Testing backup integrity..."
if gunzip -t "$BACKUP_DIR/immich.sql.gz" 2>/dev/null; then
    log "✓ Backup integrity verified"
else
    error "Backup integrity check failed!"
    exit 1
fi

log "Backup successful!"

