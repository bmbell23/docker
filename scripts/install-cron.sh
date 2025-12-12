#!/bin/bash

# Install Docker Cleanup Cron Job

SCRIPT_DIR="/home/brandon/projects/docker/scripts"
CLEANUP_SCRIPT="$SCRIPT_DIR/docker-cleanup.sh"

echo "Installing Docker cleanup cron job..."

# Check if script exists
if [ ! -f "$CLEANUP_SCRIPT" ]; then
    echo "ERROR: Cleanup script not found at $CLEANUP_SCRIPT"
    exit 1
fi

# Make sure script is executable
chmod +x "$CLEANUP_SCRIPT"

# Create cron job entries
CRON_ENTRIES="
# Docker cleanup and monitoring jobs
# Run cleanup every day at 2 AM
0 2 * * * $CLEANUP_SCRIPT >/dev/null 2>&1

# Quick stale process check every 6 hours
0 */6 * * * $CLEANUP_SCRIPT >/dev/null 2>&1

# Weekly deep cleanup on Sundays at 3 AM
0 3 * * 0 docker system prune -a -f --volumes >/dev/null 2>&1
"

# Backup existing crontab
echo "Backing up existing crontab..."
crontab -l > /tmp/crontab_backup_$(date +%Y%m%d_%H%M%S) 2>/dev/null || echo "No existing crontab found"

# Add new cron jobs (avoid duplicates)
echo "Adding cron jobs..."
(crontab -l 2>/dev/null | grep -v "docker-cleanup.sh"; echo "$CRON_ENTRIES") | crontab -

echo "Cron jobs installed successfully!"
echo ""
echo "Installed jobs:"
crontab -l | grep -E "(docker-cleanup|Docker cleanup)"
echo ""
echo "Log file location: /home/brandon/projects/docker/logs/docker-cleanup.log"
echo "To view logs: tail -f /home/brandon/projects/docker/logs/docker-cleanup.log"
echo ""
echo "To test the script manually: $CLEANUP_SCRIPT"
