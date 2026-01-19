#!/bin/bash
# Post-Reboot Verification Script
# This script verifies all Docker services are running correctly after a reboot

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FAILED_SERVICES=()
WARNINGS=()

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a container is running
check_container() {
    local container=$1
    local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not found")
    
    if [ "$status" = "running" ]; then
        log "✓ $container is running"
        return 0
    elif [ "$status" = "not found" ]; then
        error "✗ $container not found"
        FAILED_SERVICES+=("$container (not found)")
        return 1
    else
        error "✗ $container is $status"
        FAILED_SERVICES+=("$container ($status)")
        return 1
    fi
}

# Function to check container health
check_health() {
    local container=$1
    local health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no healthcheck")
    
    if [ "$health" = "healthy" ]; then
        log "  ✓ Health check: healthy"
    elif [ "$health" = "no healthcheck" ]; then
        info "  ℹ No health check configured"
    else
        warn "  ⚠ Health check: $health"
        WARNINGS+=("$container health: $health")
    fi
}

# Function to check database connectivity
check_postgres() {
    local container=$1
    local db=$2
    
    if docker exec "$container" pg_isready -U postgres > /dev/null 2>&1; then
        log "  ✓ PostgreSQL is ready"
    else
        error "  ✗ PostgreSQL is not ready"
        FAILED_SERVICES+=("$container database")
    fi
}

check_mariadb() {
    local container=$1
    
    if docker exec "$container" mysqladmin ping -h localhost > /dev/null 2>&1; then
        log "  ✓ MariaDB is ready"
    else
        error "  ✗ MariaDB is not ready"
        FAILED_SERVICES+=("$container database")
    fi
}

log "========================================="
log "Post-Reboot Verification"
log "========================================="
log ""

# Wait a bit for services to start
log "Waiting 10 seconds for services to initialize..."
sleep 10

# Check critical services
log ""
log "=== IMMICH (CRITICAL) ==="
check_container "immich_server"
check_health "immich_server"
check_container "immich_postgres"
check_health "immich_postgres"
check_postgres "immich_postgres" "immich"
check_container "immich_redis"
check_health "immich_redis"
check_container "immich_machine_learning"
check_health "immich_machine_learning"

log ""
log "=== JELLYFIN ==="
check_container "20e88449cb9d_jellyfin"
check_health "20e88449cb9d_jellyfin"

log ""
log "=== ROMM ==="
check_container "romm"
check_container "romm-db"
check_mariadb "romm-db"

log ""
log "=== OUTLINE ==="
check_container "outline"
check_health "outline"
check_container "outline_postgres"
check_health "outline_postgres"
check_postgres "outline_postgres" "outline"
check_container "outline_redis"
check_health "outline_redis"
check_container "outline_minio"
check_health "outline_minio"

log ""
log "=== MEDIA SERVICES ==="
check_container "audiobookshelf"
check_container "kavita"
check_health "kavita"
check_container "navidrome"
check_container "stash"

log ""
log "=== TORRENT SERVICES ==="
check_container "mullvad-vpn"
check_container "qbittorrent"
check_container "jackett"

log ""
log "=== OTHER SERVICES ==="
check_container "dashboard"
check_health "dashboard"
check_container "yt-dlp-web"
check_container "picard"

# Summary
log ""
log "========================================="
log "Verification Summary"
log "========================================="

if [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    log "✓ All services are running!"
else
    error "✗ ${#FAILED_SERVICES[@]} service(s) failed:"
    for service in "${FAILED_SERVICES[@]}"; do
        error "  - $service"
    done
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    warn ""
    warn "⚠ ${#WARNINGS[@]} warning(s):"
    for warning in "${WARNINGS[@]}"; do
        warn "  - $warning"
    done
fi

log ""
log "To check logs for a failed service:"
log "  docker logs <container_name>"
log ""
log "To restart a failed service:"
log "  cd /home/brandon/projects/docker/<service_dir>"
log "  docker-compose up -d"

