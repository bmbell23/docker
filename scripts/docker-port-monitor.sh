#!/bin/bash

# Docker Port Monitor Script
# Logs all container port mappings to track what's running on which ports

LOG_FILE="/home/brandon/projects/docker/logs/port-monitor.log"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "=== Docker Port Monitor ==="

# Get all running containers with their port mappings
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" | while IFS= read -r line; do
    log "$line"
done

log ""
