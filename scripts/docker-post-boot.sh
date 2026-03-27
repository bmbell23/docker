#!/bin/bash
#
# docker-post-boot.sh
#
# Post-boot recovery script that ensures all Docker containers are running
# properly after a reboot or crash. Handles:
#
#   1. Cleaning stale iptables DNAT rules for host-networked containers
#   2. Waiting for the VPN container to be ready
#   3. Restarting VPN-dependent containers (jackett, flaresolverr)
#   4. Running the tailscale-docker-routing script
#
# Installed via systemd: docker-post-boot.service
#

set -uo pipefail

LOG_FILE="/home/brandon/projects/docker/logs/post-boot.log"
DOCKER_DIR="/home/brandon/projects/docker"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Docker Post-Boot Recovery Started ==="

# ---------------------------------------------------------------
# 1. Clean stale DNAT rules for host-networked containers
#    The dashboard uses network_mode: host and listens on port 8001.
#    If any old DNAT rule exists for port 8001, it will hijack traffic.
# ---------------------------------------------------------------
log "Cleaning stale iptables DNAT rules..."

# Remove any DNAT rules targeting port 8001 (dashboard uses host networking)
while iptables -t nat -D DOCKER -p tcp -m tcp --dport 8001 -j DNAT --to-destination 172.22.0.2:5000 2>/dev/null; do
    log "  Removed stale DNAT rule for port 8001"
done

# Generic cleanup: remove DNAT rules for port 8001 regardless of destination
# (catches any stale rules even if the destination IP changes)
STALE_RULES=$(iptables -t nat -L DOCKER -n --line-numbers 2>/dev/null | grep "dpt:8001" | awk '{print $1}' | sort -rn)
for rule_num in $STALE_RULES; do
    iptables -t nat -D DOCKER "$rule_num" 2>/dev/null && \
        log "  Removed stale DNAT rule #$rule_num for port 8001"
done

log "Stale iptables cleanup complete"

# ---------------------------------------------------------------
# 2. Wait for VPN container to be running
# ---------------------------------------------------------------
log "Waiting for mullvad-vpn container..."

MAX_WAIT=120
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if docker inspect -f '{{.State.Running}}' mullvad-vpn 2>/dev/null | grep -q "true"; then
        log "  mullvad-vpn is running (waited ${WAITED}s)"
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    log "  WARNING: mullvad-vpn not running after ${MAX_WAIT}s, attempting to start torrents stack..."
    cd "$DOCKER_DIR/torrents" && docker compose up -d 2>&1 | tee -a "$LOG_FILE"
    sleep 10
fi

# ---------------------------------------------------------------
# 3. Restart VPN-dependent containers if they're not running
#    These use network_mode: container:mullvad-vpn and often fail
#    after a crash because the VPN wasn't ready when they started.
# ---------------------------------------------------------------
log "Checking VPN-dependent containers..."

VPN_CONTAINERS=("jackett" "flaresolverr")

for container in "${VPN_CONTAINERS[@]}"; do
    STATUS=$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || echo "not_found")
    if [ "$STATUS" != "true" ]; then
        log "  $container is not running (status: $STATUS), restarting..."
        docker rm -f "$container" 2>/dev/null || true
    else
        log "  $container is already running"
    fi
done

# If any VPN-dependent container was down, restart the jackett stack
NEEDS_RESTART=false
for container in "${VPN_CONTAINERS[@]}"; do
    STATUS=$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || echo "not_found")
    if [ "$STATUS" != "true" ]; then
        NEEDS_RESTART=true
        break
    fi
done

if [ "$NEEDS_RESTART" = true ]; then
    log "  Restarting jackett compose stack..."
    cd "$DOCKER_DIR/jackett" && docker compose up -d 2>&1 | tee -a "$LOG_FILE"
    sleep 5
    # Verify
    for container in "${VPN_CONTAINERS[@]}"; do
        STATUS=$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || echo "not_found")
        log "  $container status after restart: $STATUS"
    done
fi

# ---------------------------------------------------------------
# 4. Run tailscale routing (ensure Tailscale can reach containers)
# ---------------------------------------------------------------
log "Setting up Tailscale Docker routing..."
if [ -x "$DOCKER_DIR/scripts/tailscale-docker-routing.sh" ]; then
    bash "$DOCKER_DIR/scripts/tailscale-docker-routing.sh" 2>&1 | tee -a "$LOG_FILE"
fi

# ---------------------------------------------------------------
# 5. Final status check
# ---------------------------------------------------------------
log "=== Final Container Status ==="
docker ps -a --format "{{.Names}}: {{.Status}}" | sort | while read line; do
    log "  $line"
done

EXITED=$(docker ps -a --filter "status=exited" --format "{{.Names}}" | wc -l)
log "=== Docker Post-Boot Recovery Complete (${EXITED} containers exited) ==="

