#!/bin/bash
# Setup Automated Backups
# This script sets up a cron job to automatically backup Immich daily

set -e

echo "Setting up automated Immich backups..."

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "immich-daily-backup.sh"; then
    echo "Cron job already exists. Removing old entry..."
    crontab -l | grep -v "immich-daily-backup.sh" | crontab -
fi

# Add new cron job (runs at 2 AM daily)
(crontab -l 2>/dev/null; echo "0 2 * * * /home/brandon/projects/docker/immich-daily-backup.sh >> /home/brandon/backups/immich-daily/cron.log 2>&1") | crontab -

echo "✓ Automated backup configured!"
echo ""
echo "Immich will be backed up daily at 2:00 AM"
echo "Backups will be stored in: /home/brandon/backups/immich-daily/"
echo "Backups older than 7 days will be automatically deleted"
echo ""
echo "To view current cron jobs:"
echo "  crontab -l"
echo ""
echo "To manually run a backup now:"
echo "  /home/brandon/projects/docker/immich-daily-backup.sh"
echo ""
echo "To view backup logs:"
echo "  tail -f /home/brandon/backups/immich-daily/backup.log"

