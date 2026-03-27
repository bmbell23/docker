#!/bin/bash
# immich-watchdog: kills the immich container if disk or swap crosses
# critical thresholds, preventing it from taking down the whole server.
# Runs every 5 minutes via cron. Immich restarts automatically (unless-stopped).

LOG=/var/log/immich-watchdog.log

# Thresholds
DOCKER_DISK_WARN=80   # % — log a warning
DOCKER_DISK_CRIT=88   # % — kill immich
NAS_DISK_WARN=85      # % — log a warning
NAS_DISK_CRIT=93      # % — kill immich
SWAP_WARN=60          # % — log a warning
SWAP_CRIT=80          # % — kill immich

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

kill_immich() {
    local reason="$1"
    PID=$(docker inspect immich --format '{{.State.Pid}}' 2>/dev/null)
    if [ -n "$PID" ] && [ "$PID" != "0" ]; then
        log "CRITICAL [$reason] — stopping immich (PID $PID). Will auto-restart."
        kill "$PID"
    else
        log "CRITICAL [$reason] — immich not running or already stopped."
    fi
}

# --- Docker data disk (/mnt/docker) ---
DOCKER_PCT=$(df /mnt/docker 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
if [ -n "$DOCKER_PCT" ]; then
    if [ "$DOCKER_PCT" -ge "$DOCKER_DISK_CRIT" ]; then
        kill_immich "Docker disk at ${DOCKER_PCT}%"
    elif [ "$DOCKER_PCT" -ge "$DOCKER_DISK_WARN" ]; then
        log "WARNING: Docker disk at ${DOCKER_PCT}% (kill threshold: ${DOCKER_DISK_CRIT}%)"
    fi
fi

# --- NAS disk (/mnt/boston — where immich thumbnails live) ---
NAS_PCT=$(df /mnt/boston 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
if [ -n "$NAS_PCT" ]; then
    if [ "$NAS_PCT" -ge "$NAS_DISK_CRIT" ]; then
        kill_immich "NAS disk at ${NAS_PCT}%"
    elif [ "$NAS_PCT" -ge "$NAS_DISK_WARN" ]; then
        log "WARNING: NAS disk at ${NAS_PCT}% (kill threshold: ${NAS_DISK_CRIT}%)"
    fi
fi

# --- Swap ---
SWAP_TOTAL=$(free | awk '/Swap/{print $2}')
SWAP_USED=$(free  | awk '/Swap/{print $3}')
if [ "$SWAP_TOTAL" -gt 0 ]; then
    SWAP_PCT=$(awk "BEGIN{printf \"%.0f\", $SWAP_USED/$SWAP_TOTAL*100}")
    if [ "$SWAP_PCT" -ge "$SWAP_CRIT" ]; then
        kill_immich "Swap at ${SWAP_PCT}%"
    elif [ "$SWAP_PCT" -ge "$SWAP_WARN" ]; then
        log "WARNING: Swap at ${SWAP_PCT}% (kill threshold: ${SWAP_CRIT}%)"
    fi
fi

