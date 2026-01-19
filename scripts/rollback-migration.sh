#!/bin/bash
set -e

# Rollback script: Restore Snap Docker if migration fails
# This script reverts the migration and restores Snap Docker

BACKUP_DIR="/home/brandon/docker-migration-backup"
LOG_FILE="$BACKUP_DIR/rollback_$(date +%Y%m%d_%H%M%S).log"
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
    error "Cannot rollback without backup!"
    exit 1
fi

echo "========================================" | tee -a "$LOG_FILE"
echo "Docker Migration Rollback" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Confirmation prompt
echo ""
echo "⚠️  WARNING: This will restore Snap Docker and stop native Docker"
echo ""
read -p "Are you sure you want to rollback? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Rollback cancelled."
    exit 0
fi

log "Step 1: Stopping all containers on native Docker..."
docker ps -q | xargs -r docker stop || warn "Some containers failed to stop"

log "Step 2: Stopping native Docker daemon..."
systemctl stop docker.service || warn "Failed to stop native Docker"
systemctl disable docker.service || warn "Failed to disable native Docker"

log "Step 3: Reinstalling Snap Docker..."
snap install docker || error "Failed to install Snap Docker"

log "Step 4: Starting Snap Docker daemon..."
systemctl start snap.docker.dockerd.service
systemctl enable snap.docker.dockerd.service
sleep 5

# Verify Snap Docker is running
if ! /snap/bin/docker info > /dev/null 2>&1; then
    error "Snap Docker failed to start!"
    exit 1
fi

log "Step 5: Recreating containers from docker-compose files..."

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
        /snap/bin/docker compose up -d 2>&1 | tee -a "$LOG_FILE" || warn "Failed to start $dir"
    fi
done

log "Step 6: Waiting for containers to start..."
sleep 10

log "Step 7: Verifying containers are running..."
RUNNING_NOW=$(/snap/bin/docker ps -q | wc -l)
log "  Containers running: $RUNNING_NOW"

log "Step 8: Applying iptables rules..."
"$PROJECT_DIR/scripts/fix-all-docker-iptables.sh" 2>&1 | tee -a "$LOG_FILE" || warn "Failed to apply iptables rules"

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
log "Rollback completed!" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "📊 ROLLBACK SUMMARY" | tee -a "$LOG_FILE"
echo "  Snap Docker: $(systemctl is-active snap.docker.dockerd.service)" | tee -a "$LOG_FILE"
echo "  Native Docker: $(systemctl is-active docker.service)" | tee -a "$LOG_FILE"
echo "  Containers running: $RUNNING_NOW" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "⚠️  NOTE: You will need to use the PID kill workaround again:" | tee -a "$LOG_FILE"
echo "  PID=\$(docker inspect <container> --format '{{.State.Pid}}')" | tee -a "$LOG_FILE"
echo "  sudo kill \$PID" | tee -a "$LOG_FILE"
echo "  docker compose up -d" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

