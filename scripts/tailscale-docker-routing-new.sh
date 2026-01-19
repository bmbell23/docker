#!/bin/bash
# Allow Tailscale to access Docker containers
# This fixes the issue where Docker containers aren't accessible via Tailscale IP

LOG_FILE="/home/brandon/projects/docker/logs/tailscale-routing.log"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Tailscale Docker Routing Script Started ==="

# Allow traffic from Tailscale to Docker
log "Adding DOCKER-USER iptables rules..."
iptables -I DOCKER-USER -i tailscale0 -j ACCEPT 2>/dev/null || log "WARNING: Failed to add DOCKER-USER input rule"
iptables -I DOCKER-USER -o tailscale0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || log "WARNING: Failed to add DOCKER-USER output rule"

# Allow forwarding between Tailscale and Docker networks
log "Configuring forwarding rules for Docker bridges..."
BRIDGE_COUNT=0
for network_id in $(docker network ls --format '{{.ID}}'); do
    network_name=$(docker network inspect "$network_id" --format '{{.Name}}' 2>/dev/null)
    if [ "$network_name" = "host" ] || [ "$network_name" = "none" ]; then
        continue
    fi
    
    bridge="br-${network_id}"
    if ip link show "$bridge" >/dev/null 2>&1; then
        iptables -I FORWARD -i tailscale0 -o "$bridge" -j ACCEPT 2>/dev/null || log "WARNING: Failed to add forward rule for $bridge"
        iptables -I FORWARD -i "$bridge" -o tailscale0 -j ACCEPT 2>/dev/null || log "WARNING: Failed to add reverse forward rule for $bridge"
        log "  Added forwarding rules for bridge: $bridge (network: $network_name)"
        BRIDGE_COUNT=$((BRIDGE_COUNT + 1))
    fi
done

log "Tailscale Docker routing enabled for $BRIDGE_COUNT bridges"
log "=== Tailscale Docker Routing Script Completed ==="
echo ""
