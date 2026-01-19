#!/bin/bash
set -e

# Backup script before Snap to Native Docker migration
# This creates a complete backup of all Docker configurations and data

BACKUP_DIR="/home/brandon/docker-migration-backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory first
mkdir -p "$BACKUP_DIR"

LOG_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.log"

echo "========================================" | tee -a "$LOG_FILE"
echo "Docker Migration Backup Script" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

mkdir -p "$BACKUP_DIR/compose-files"
mkdir -p "$BACKUP_DIR/volumes"
mkdir -p "$BACKUP_DIR/configs"

# Function to log messages
log() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"
}

log "Step 1: Creating inventory of current Docker state..."

# Save current state
docker ps -a > "$BACKUP_DIR/containers_list.txt" 2>&1
docker volume ls > "$BACKUP_DIR/volumes_list.txt" 2>&1
docker network ls > "$BACKUP_DIR/networks_list.txt" 2>&1
docker images > "$BACKUP_DIR/images_list.txt" 2>&1

log "Step 2: Backing up all docker-compose files..."

# Copy all docker-compose files
cd /home/brandon/projects/docker
find . -name "docker-compose.yml" -o -name "docker-compose.yaml" | while read -r file; do
    dir=$(dirname "$file")
    mkdir -p "$BACKUP_DIR/compose-files/$dir"
    cp "$file" "$BACKUP_DIR/compose-files/$file"
    log "  Backed up: $file"
done

log "Step 3: Backing up critical configuration directories..."

# Backup important config directories (not full volumes, just configs)
CRITICAL_CONFIGS=(
    "jellyfin"
    "outline"
    "immich-main"
    "audiobookshelf"
    "kavita"
    "navidrome"
    "stash"
    "romm"
)

for config in "${CRITICAL_CONFIGS[@]}"; do
    if [ -d "/home/brandon/projects/docker/$config" ]; then
        log "  Backing up config: $config"
        cp -r "/home/brandon/projects/docker/$config" "$BACKUP_DIR/configs/" 2>&1 | tee -a "$LOG_FILE" || true
    fi
done

log "Step 4: Documenting volume locations..."

# Document where volumes are stored
docker volume inspect $(docker volume ls -q) > "$BACKUP_DIR/volume_details.json" 2>&1 || true

log "Step 5: Backing up Docker daemon configuration..."

# Backup Snap Docker config
if [ -d "/var/snap/docker" ]; then
    log "  Snap Docker config found"
    echo "/var/snap/docker" > "$BACKUP_DIR/snap_docker_location.txt"
fi

# Backup native Docker config
if [ -f "/etc/docker/daemon.json" ]; then
    cp "/etc/docker/daemon.json" "$BACKUP_DIR/daemon.json"
    log "  Native Docker daemon.json backed up"
fi

log "Step 6: Creating inventory summary..."

# Create comprehensive inventory
cat > "$BACKUP_DIR/inventory.txt" << EOF
Docker Migration Backup Inventory
Created: $(date)

CONTAINERS ($(docker ps -a | wc -l) total):
$(docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Image}}")

VOLUMES ($(docker volume ls | wc -l) total):
$(docker volume ls --format "{{.Name}}")

NETWORKS ($(docker network ls | wc -l) total):
$(docker network ls --format "{{.Name}}\t{{.Driver}}")

DOCKER-COMPOSE FILES:
$(find /home/brandon/projects/docker -name "docker-compose.yml" -o -name "docker-compose.yaml")

SNAP DOCKER DAEMON:
PID: $(pgrep -f "snap.docker.dockerd" || echo "Not running")
Status: $(systemctl is-active snap.docker.dockerd.service || echo "Unknown")

NATIVE DOCKER DAEMON:
PID: $(pgrep -f "/usr/bin/dockerd" || echo "Not running")
Status: $(systemctl is-active docker.service || echo "Unknown")

DISK USAGE:
$(df -h /var/snap/docker 2>/dev/null || echo "Snap Docker: Not found")
$(df -h /var/lib/docker 2>/dev/null || echo "Native Docker: Not found")
EOF

log "Step 7: Calculating backup size..."

BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log "  Backup size: $BACKUP_SIZE"

log "Step 8: Creating backup verification checksum..."

find "$BACKUP_DIR" -type f -exec md5sum {} \; > "$BACKUP_DIR/checksums.txt"

log "========================================" | tee -a "$LOG_FILE"
log "Backup completed successfully!" | tee -a "$LOG_FILE"
log "Backup location: $BACKUP_DIR" | tee -a "$LOG_FILE"
log "Backup size: $BACKUP_SIZE" | tee -a "$LOG_FILE"
log "========================================" | tee -a "$LOG_FILE"

echo ""
echo "✅ BACKUP COMPLETE"
echo ""
echo "Review the inventory:"
echo "  cat $BACKUP_DIR/inventory.txt"
echo ""
echo "Review the backup log:"
echo "  cat $LOG_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the inventory to ensure all critical services are listed"
echo "  2. When ready to migrate, run: sudo /home/brandon/projects/docker/scripts/migrate-snap-to-native.sh"
echo ""

