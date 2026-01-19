#!/bin/bash
# Pre-Reboot Backup Script
# This script backs up all critical Docker services before a server reboot
# Run this BEFORE rebooting to ensure you can recover from any issues

set -e  # Exit on error

BACKUP_ROOT="/home/brandon/backups/pre-reboot-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$BACKUP_ROOT/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Create backup directory
mkdir -p "$BACKUP_ROOT"
log "Created backup directory: $BACKUP_ROOT"

# Function to backup a database container
backup_postgres() {
    local container=$1
    local db_name=$2
    local backup_file="$BACKUP_ROOT/${container}_${db_name}.sql"
    
    log "Backing up PostgreSQL database: $container ($db_name)"
    if docker exec "$container" pg_dump -U postgres "$db_name" > "$backup_file"; then
        gzip "$backup_file"
        log "✓ PostgreSQL backup complete: ${backup_file}.gz"
    else
        error "✗ Failed to backup PostgreSQL: $container"
        return 1
    fi
}

backup_mariadb() {
    local container=$1
    local db_name=$2
    local backup_file="$BACKUP_ROOT/${container}_${db_name}.sql"
    
    log "Backing up MariaDB database: $container ($db_name)"
    if docker exec "$container" mysqldump -u root -promm-root-password "$db_name" > "$backup_file"; then
        gzip "$backup_file"
        log "✓ MariaDB backup complete: ${backup_file}.gz"
    else
        error "✗ Failed to backup MariaDB: $container"
        return 1
    fi
}

# Function to backup a directory
backup_directory() {
    local source=$1
    local name=$2
    local backup_file="$BACKUP_ROOT/${name}.tar.gz"
    
    if [ ! -d "$source" ]; then
        warn "Directory not found: $source"
        return 1
    fi
    
    log "Backing up directory: $source"
    if tar -czf "$backup_file" -C "$(dirname "$source")" "$(basename "$source")"; then
        log "✓ Directory backup complete: $backup_file"
    else
        error "✗ Failed to backup directory: $source"
        return 1
    fi
}

log "========================================="
log "Starting Pre-Reboot Backup"
log "========================================="

# 1. IMMICH - CRITICAL (PostgreSQL database + config)
log ""
log "=== IMMICH BACKUP ==="
backup_postgres "immich_postgres" "immich" || warn "Immich database backup failed"
backup_directory "/home/brandon/immich/postgres" "immich_postgres_data" || warn "Immich postgres data backup failed"

# 2. OUTLINE - PostgreSQL + MinIO + Redis
log ""
log "=== OUTLINE BACKUP ==="
backup_postgres "outline_postgres" "outline" || warn "Outline database backup failed"
backup_directory "/home/brandon/projects/docker/outline/data" "outline_data" || warn "Outline data backup failed"

# 3. ROMM - MariaDB database
log ""
log "=== ROMM BACKUP ==="
backup_mariadb "romm-db" "romm" || warn "Romm database backup failed"
backup_directory "/home/brandon/romm" "romm_data" || warn "Romm data backup failed"

# 4. JELLYFIN - Config and database
log ""
log "=== JELLYFIN BACKUP ==="
backup_directory "/home/brandon/jellyfin/config" "jellyfin_config" || warn "Jellyfin config backup failed"

# 5. AUDIOBOOKSHELF - Config and database
log ""
log "=== AUDIOBOOKSHELF BACKUP ==="
backup_directory "/home/brandon/audiobookshelf/data" "audiobookshelf_data" || warn "Audiobookshelf data backup failed"

# 6. KAVITA - Config and database
log ""
log "=== KAVITA BACKUP ==="
backup_directory "/home/brandon/kavita/data" "kavita_data" || warn "Kavita data backup failed"

# 7. NAVIDROME - Config and database
log ""
log "=== NAVIDROME BACKUP ==="
backup_directory "/home/brandon/navidrome/data" "navidrome_data" || warn "Navidrome data backup failed"

# 8. STASH - Config and database
log ""
log "=== STASH BACKUP ==="
backup_directory "/home/brandon/stash/config" "stash_config" || warn "Stash config backup failed"

# 9. Save current container states
log ""
log "=== SAVING CONTAINER STATES ==="
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" > "$BACKUP_ROOT/container_states.txt"
log "✓ Container states saved"

# 10. Save docker-compose files
log ""
log "=== BACKING UP DOCKER-COMPOSE FILES ==="
find /home/brandon/projects -name "docker-compose.yml" -o -name "docker-compose.yaml" | while read -r file; do
    cp "$file" "$BACKUP_ROOT/$(echo "$file" | sed 's/\//_/g')"
done
log "✓ Docker-compose files backed up"

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_ROOT" | cut -f1)

log ""
log "========================================="
log "Backup Complete!"
log "========================================="
log "Backup location: $BACKUP_ROOT"
log "Backup size: $BACKUP_SIZE"
log "Log file: $LOG_FILE"
log ""
log "You can now safely reboot the server."
log "After reboot, run: ./post-reboot-verify.sh"

