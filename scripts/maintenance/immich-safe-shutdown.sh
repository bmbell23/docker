#!/bin/bash
# Immich Safe Shutdown Script
# This script safely shuts down Immich to prevent database corruption
# CRITICAL: Run this BEFORE rebooting to prevent data loss

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log "========================================="
log "Immich Safe Shutdown"
log "========================================="
log ""

# Check if Immich is running
if ! docker ps | grep -q immich_server; then
    warn "Immich is not running"
    exit 0
fi

# Step 1: Create a backup first
log "Step 1: Creating database backup..."
BACKUP_DIR="/home/brandon/backups/immich-shutdown-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if docker exec immich_postgres pg_dump -U postgres immich > "$BACKUP_DIR/immich.sql"; then
    gzip "$BACKUP_DIR/immich.sql"
    log "✓ Database backup created: $BACKUP_DIR/immich.sql.gz"
else
    error "✗ Failed to create backup!"
    exit 1
fi

# Step 2: Stop Immich server (stops new connections)
log ""
log "Step 2: Stopping Immich server..."
cd /home/brandon/projects/docker/immich-main
docker-compose stop immich-server
log "✓ Immich server stopped"

# Step 3: Stop machine learning
log ""
log "Step 3: Stopping machine learning..."
docker-compose stop immich-machine-learning
log "✓ Machine learning stopped"

# Step 4: Gracefully stop PostgreSQL (allows it to flush buffers)
log ""
log "Step 4: Gracefully stopping PostgreSQL..."
log "  Sending SIGTERM to allow graceful shutdown..."
docker exec immich_postgres pg_ctl stop -D /var/lib/postgresql/data -m smart || true
sleep 5

# Step 5: Stop the container
log "  Stopping container..."
docker-compose stop database
log "✓ PostgreSQL stopped gracefully"

# Step 6: Stop Redis
log ""
log "Step 5: Stopping Redis..."
docker-compose stop redis
log "✓ Redis stopped"

# Verify all stopped
log ""
log "Verifying all Immich containers are stopped..."
if docker ps | grep -q immich; then
    error "Some Immich containers are still running!"
    docker ps | grep immich
    exit 1
else
    log "✓ All Immich containers stopped"
fi

log ""
log "========================================="
log "Immich Safely Shut Down"
log "========================================="
log "Backup location: $BACKUP_DIR"
log ""
log "After reboot, Immich will automatically restart."
log "To manually start Immich:"
log "  cd /home/brandon/projects/docker/immich-main"
log "  docker-compose up -d"

