#!/bin/bash

# Database Backup Script
# Backs up all important Docker databases to NAS

BACKUP_DIR="/mnt/boston/docker-backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "Starting database backups at $(date)"

# Immich Postgres Backup
echo "Backing up Immich database..."
docker exec immich_postgres pg_dump -U postgres immich | gzip > "$BACKUP_DIR/immich_${DATE}.sql.gz"
if [ $? -eq 0 ]; then
    echo "✓ Immich backup successful"
else
    echo "✗ Immich backup failed"
fi

# RomM MariaDB Backup
echo "Backing up RomM database..."
docker exec romm-db mariadb-dump -u romm -promm romm | gzip > "$BACKUP_DIR/romm_${DATE}.sql.gz"
if [ $? -eq 0 ]; then
    echo "✓ RomM backup successful"
else
    echo "✗ RomM backup failed"
fi

# Jellyfin SQLite Backup (if needed)
echo "Backing up Jellyfin database..."
docker exec jellyfin cp /config/data/jellyfin.db /config/data/jellyfin_backup.db
docker cp jellyfin:/config/data/jellyfin_backup.db "$BACKUP_DIR/jellyfin_${DATE}.db"
if [ $? -eq 0 ]; then
    echo "✓ Jellyfin backup successful"
    docker exec jellyfin rm /config/data/jellyfin_backup.db
else
    echo "✗ Jellyfin backup failed"
fi

# Clean up old backups (older than RETENTION_DAYS)
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "*.db" -mtime +$RETENTION_DAYS -delete

echo "Backup completed at $(date)"
echo "Backups stored in: $BACKUP_DIR"

