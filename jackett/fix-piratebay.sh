#!/bin/bash

# Script to fix The Pirate Bay indexer in Jackett
# This script removes the problematic num_files selector

echo "Fixing The Pirate Bay indexer configuration..."

# Stop Jackett
docker-compose down

# Find and backup the indexer config
CONFIG_DIR="/home/brandon/jackett/config"
if [ -d "$CONFIG_DIR" ]; then
    echo "Found Jackett config directory: $CONFIG_DIR"
    
    # Look for Pirate Bay config files
    find "$CONFIG_DIR" -name "*pirate*" -type f 2>/dev/null | while read file; do
        echo "Found config file: $file"
        # Create backup
        cp "$file" "$file.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Created backup: $file.backup.$(date +%Y%m%d_%H%M%S)"
    done
else
    echo "Config directory not found. Using Docker volume."
fi

# Restart Jackett
docker-compose up -d

echo "Jackett restarted. Please:"
echo "1. Go to http://100.123.154.40:9117"
echo "2. Remove The Pirate Bay indexer"
echo "3. Re-add it from the indexer list"
echo "4. Test the indexer"
