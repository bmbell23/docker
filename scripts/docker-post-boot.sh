#!/bin/bash
#
# docker-post-boot.sh
#
# Post-boot recovery script that ensures all Docker containers are running
# properly after a reboot or crash. Handles:
#
#   1. Cleaning stale iptables DNAT rules for host-networked containers
#   2. Waiting for the VPN container to be ready
#   3. Starting containers that share the VPN's network, then dropping
#      any DNAT rule that points at a dead container IP
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
# 3. Start containers that share another container's network
#    (network_mode: container:mullvad-vpn: qbittorrent, jackett,
#    flaresolverr). If dockerd starts one before its VPN is up it
#    fails with "cannot join network namespace of a non running
#    container" and never retries (qbittorrent, 2026-09-30, docker#34).
# ---------------------------------------------------------------
log "Checking containers that share another container's network..."
for id in $(docker ps -aq); do
    read -r name mode policy running <<<"$(docker inspect -f '{{.Name}} {{.HostConfig.NetworkMode}} {{.HostConfig.RestartPolicy.Name}} {{.State.Running}}' "$id")"
    name=${name#/}
    case "$mode" in container:*) ;; *) continue ;; esac
    [ "$running" = true ] && { log "  $name is already running"; continue; }
    [ "$policy" = "no" ] && { log "  $name is down but has no restart policy; leaving it"; continue; }
    parent=${mode#container:}
    if [ "$(docker inspect -f '{{.State.Running}}' "$parent" 2>/dev/null)" != true ]; then
        log "  WARNING: $name is down and its network parent $parent isn't running"
        continue
    fi
    if docker start "$name" >/dev/null 2>&1; then
        log "  started $name"
    else
        # The parent was recreated (new id): compose re-points it at the new one.
        dir=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$name")
        svc=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$name")
        log "  docker start $name failed; compose up -d $svc in $dir"
        [ -n "$dir" ] && [ -n "$svc" ] && (cd "$dir" && docker compose up -d "$svc" 2>&1 | tee -a "$LOG_FILE")
    fi
done

# ---------------------------------------------------------------
# 3b. Drop DNAT rules that point at IPs no running container has.
#     Docker owns every live rule; anything else is left over and
#     can hijack Tailscale traffic (docker#34).
# ---------------------------------------------------------------
log "Cleaning stale DNAT rules..."
"$DOCKER_DIR/scripts/maintenance/clean-stale-dnat.sh" 2>&1 | tee -a "$LOG_FILE"

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

