#!/bin/bash
set -e

# Migration script: Snap Docker to Native Docker
# This script migrates all containers from Snap Docker to native Docker

BACKUP_DIR="/home/brandon/docker-migration-backup"
LOG_FILE="$BACKUP_DIR/migration_$(date +%Y%m%d_%H%M%S).log"
PROJECT_DIR="/home/brandon/projects/docker"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root (use sudo)"
    exit 1
fi

# Check if backup exists
if [ ! -d "$BACKUP_DIR" ]; then
    error "Backup directory not found: $BACKUP_DIR"
    error "Please run backup script first: sudo /home/brandon/projects/docker/scripts/backup-before-migration.sh"
    exit 1
fi

echo "========================================" | tee -a "$LOG_FILE"
echo "Docker Migration: Snap to Native" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Confirmation prompt
echo ""
echo "⚠️  WARNING: This will stop all Docker containers and migrate to native Docker"
echo ""
echo "Estimated downtime: 30-60 minutes"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

log "Step 1: Saving current container list..."
docker ps --format "{{.Names}}" > "$BACKUP_DIR/running_containers.txt"
CONTAINER_COUNT=$(wc -l < "$BACKUP_DIR/running_containers.txt")
log "  Found $CONTAINER_COUNT running containers"

log "Step 2: Stopping all containers gracefully..."
docker ps -q | xargs -r docker stop || warn "Some containers failed to stop gracefully"

log "Step 3: Verifying all containers are stopped..."
RUNNING=$(docker ps -q | wc -l)
if [ "$RUNNING" -gt 0 ]; then
    warn "$RUNNING containers still running, force stopping..."
    docker ps -q | while read -r container; do
        PID=$(docker inspect "$container" --format '{{.State.Pid}}')
        if [ -n "$PID" ] && [ "$PID" != "0" ]; then
            kill "$PID" 2>/dev/null || true
        fi
    done
    sleep 5
fi

log "Step 4: Stopping Snap Docker daemon..."
systemctl stop snap.docker.dockerd.service || warn "Failed to stop Snap Docker service"
systemctl disable snap.docker.dockerd.service || warn "Failed to disable Snap Docker service"

log "Step 5: Removing Snap Docker..."
snap remove docker || error "Failed to remove Snap Docker"

log "Step 6: Configuring native Docker..."
# Ensure native Docker is enabled
systemctl enable docker.service
systemctl enable docker.socket

log "Step 7: Starting native Docker daemon..."
systemctl start docker.service
sleep 5

# Verify Docker is running
if ! docker info > /dev/null 2>&1; then
    error "Native Docker failed to start!"
    exit 1
fi

log "Step 8: Verifying Docker installation..."
DOCKER_VERSION=$(docker --version)
log "  Docker version: $DOCKER_VERSION"
log "  Docker daemon: $(systemctl is-active docker.service)"

log "Step 9: Recreating containers from docker-compose files..."

# List of directories with docker-compose files
COMPOSE_DIRS=(
    "audiobookshelf"
    "beets"
    "immich-main"
    "jackett"
    "jellyfin"
    "kavita"
    "navidrome"
    "outline"
    "picard"
    "romm"
    "stash"
    "torrents"
    "youtube-downloader"
)

cd "$PROJECT_DIR"

for dir in "${COMPOSE_DIRS[@]}"; do
    if [ -f "$dir/docker-compose.yml" ]; then
        log "  Starting: $dir"
        cd "$PROJECT_DIR/$dir"
        docker compose up -d 2>&1 | tee -a "$LOG_FILE" || warn "Failed to start $dir"
    else
        warn "  No docker-compose.yml found in $dir"
    fi
done

log "Step 10: Waiting for containers to start..."
sleep 10

log "Step 11: Verifying containers are running..."
RUNNING_NOW=$(docker ps -q | wc -l)
log "  Containers running: $RUNNING_NOW (expected: ~$CONTAINER_COUNT)"

if [ "$RUNNING_NOW" -lt $((CONTAINER_COUNT - 5)) ]; then
    warn "Fewer containers running than expected!"
    warn "Expected: ~$CONTAINER_COUNT, Running: $RUNNING_NOW"
fi

log "Step 12: Applying iptables rules for Tailscale access..."
"$PROJECT_DIR/scripts/fix-all-docker-iptables.sh" 2>&1 | tee -a "$LOG_FILE" || warn "Failed to apply iptables rules"

log "Step 13: Testing Docker commands..."
# Test that restart/kill/stop work without permission denied
TEST_CONTAINER=$(docker ps --format "{{.Names}}" | head -1)
if [ -n "$TEST_CONTAINER" ]; then
    log "  Testing restart on: $TEST_CONTAINER"
    if docker restart "$TEST_CONTAINER" 2>&1 | tee -a "$LOG_FILE"; then
        log "  ✅ Docker restart works!"
    else
        error "  ❌ Docker restart failed!"
    fi
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
log "Migration completed!" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Summary
echo "" | tee -a "$LOG_FILE"
echo "📊 MIGRATION SUMMARY" | tee -a "$LOG_FILE"
echo "  Containers before: $CONTAINER_COUNT" | tee -a "$LOG_FILE"
echo "  Containers after:  $RUNNING_NOW" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "✅ NEXT STEPS:" | tee -a "$LOG_FILE"
echo "  1. Verify all containers: docker ps" | tee -a "$LOG_FILE"
echo "  2. Test Jellyfin via Tailscale: curl -I http://100.123.154.40:8096" | tee -a "$LOG_FILE"
echo "  3. Test restart command: docker restart jellyfin" | tee -a "$LOG_FILE"
echo "  4. Check logs: cat $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "🎉 Docker restart/kill/stop commands should now work without permission denied!" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

