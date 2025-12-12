#!/bin/bash

# Docker Cleanup and Port Monitor Script
# Prevents stale docker-proxy processes and cleans up Docker resources

LOG_FILE="/home/brandon/projects/docker/logs/docker-cleanup.log"
IMMICH_DIR="/home/brandon/projects/docker/immich-main"
ALERT_EMAIL=""  # Set your email for alerts

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check for stale docker-proxy processes
check_stale_proxies() {
    log "Checking for stale docker-proxy processes..."
    
    # Check for docker-proxy processes holding port 2283
    STALE_PROXIES=$(ps aux | grep "docker-proxy.*2283" | grep -v grep | awk '{print $2}')
    
    if [ ! -z "$STALE_PROXIES" ]; then
        log "WARNING: Found stale docker-proxy processes for port 2283: $STALE_PROXIES"
        
        # Check if Immich containers are actually running
        cd "$IMMICH_DIR"
        RUNNING_CONTAINERS=$(docker compose ps --services --filter "status=running" 2>/dev/null)
        
        if [ -z "$RUNNING_CONTAINERS" ]; then
            log "No Immich containers running, killing stale proxies..."
            echo "$STALE_PROXIES" | xargs -r sudo kill -9
            log "Killed stale docker-proxy processes: $STALE_PROXIES"
            
            # Send alert if email is configured
            if [ ! -z "$ALERT_EMAIL" ]; then
                echo "Killed stale docker-proxy processes on $(hostname) at $(date)" | \
                mail -s "Docker Cleanup: Killed Stale Processes" "$ALERT_EMAIL"
            fi
        else
            log "Immich containers are running, proxies are legitimate"
        fi
    else
        log "No stale docker-proxy processes found"
    fi
}

# Function to clean up Docker resources
cleanup_docker() {
    log "Performing Docker cleanup..."
    
    # Clean up unused containers, networks, images
    CLEANUP_OUTPUT=$(docker system prune -f 2>&1)
    if [ $? -eq 0 ]; then
        log "Docker system cleanup completed"
        echo "$CLEANUP_OUTPUT" | grep -E "(Deleted|Total reclaimed)" | while read line; do
            log "  $line"
        done
    else
        log "ERROR: Docker system cleanup failed: $CLEANUP_OUTPUT"
    fi
    
    # Clean up unused networks
    NETWORK_CLEANUP=$(docker network prune -f 2>&1)
    if [ $? -eq 0 ]; then
        log "Docker network cleanup completed"
    else
        log "ERROR: Docker network cleanup failed: $NETWORK_CLEANUP"
    fi
}

# Function to check Docker daemon health
check_docker_health() {
    log "Checking Docker daemon health..."
    
    if ! systemctl is-active --quiet docker; then
        log "ERROR: Docker daemon is not running!"
        if [ ! -z "$ALERT_EMAIL" ]; then
            echo "Docker daemon is down on $(hostname) at $(date)" | \
            mail -s "ALERT: Docker Daemon Down" "$ALERT_EMAIL"
        fi
        return 1
    fi
    
    # Test Docker functionality
    if ! docker info >/dev/null 2>&1; then
        log "ERROR: Docker daemon is unresponsive!"
        return 1
    fi
    
    log "Docker daemon is healthy"
    return 0
}

# Function to check Immich service health
check_immich_health() {
    log "Checking Immich service health..."
    
    cd "$IMMICH_DIR"
    
    # Check if containers are running
    RUNNING=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
    EXPECTED=4  # immich-server, database, redis, machine-learning
    
    if [ "$RUNNING" -eq "$EXPECTED" ]; then
        # Test API endpoint
        if curl -s --max-time 10 http://localhost:2283/api/server/ping | grep -q "pong"; then
            log "Immich is healthy (all $RUNNING containers running, API responding)"
        else
            log "WARNING: Immich containers running but API not responding"
        fi
    elif [ "$RUNNING" -eq 0 ]; then
        log "Immich is stopped (no containers running)"
    else
        log "WARNING: Immich partially running ($RUNNING/$EXPECTED containers)"
        docker compose ps | while read line; do
            log "  $line"
        done
    fi
}

# Main execution
main() {
    log "=== Docker Cleanup Script Started ==="
    
    # Check Docker daemon first
    if ! check_docker_health; then
        log "=== Script aborted due to Docker daemon issues ==="
        exit 1
    fi
    
    # Check for stale processes
    check_stale_proxies
    
    # Perform cleanup
    cleanup_docker
    
    # Check Immich health
    check_immich_health
    
    log "=== Docker Cleanup Script Completed ==="
    echo "" >> "$LOG_FILE"  # Add blank line for readability
}

# Run main function
main "$@"
