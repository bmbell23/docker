#!/bin/bash

# Fix The Pirate Bay indexer definition by removing the problematic num_files selector

echo "Fixing The Pirate Bay indexer definition..."

# Create the custom definition directory if it doesn't exist
docker-compose exec jackett mkdir -p /config/cardigann/definitions

# Copy the original definition
docker-compose exec jackett cp /app/Jackett/Definitions/thepiratebay.yml /config/cardigann/definitions/thepiratebay-fixed.yml

# Remove the problematic files field that uses num_files selector
docker-compose exec jackett sed -i '/files:/,+1d' /config/cardigann/definitions/thepiratebay-fixed.yml

# Change the ID and name to distinguish it from the original
docker-compose exec jackett sed -i 's/id: thepiratebay/id: thepiratebay-fixed/' /config/cardigann/definitions/thepiratebay-fixed.yml
docker-compose exec jackett sed -i 's/name: The Pirate Bay/name: The Pirate Bay (Fixed)/' /config/cardigann/definitions/thepiratebay-fixed.yml

echo "Fixed indexer definition created!"
echo "Restarting Jackett to load the new definition..."

# Restart Jackett to load the new definition
docker-compose restart jackett

echo "Waiting for Jackett to start..."
sleep 10

echo "✅ The Pirate Bay (Fixed) indexer should now be available!"
echo
echo "Next steps:"
echo "1. Go to Jackett web UI: http://100.123.154.40:9117"
echo "2. Remove the old 'The Pirate Bay' indexer"
echo "3. Add the new 'The Pirate Bay (Fixed)' indexer"
echo "4. Test the new indexer"
echo
echo "If you still have issues, use these reliable alternatives:"
echo "- TorrentGalaxy"
echo "- LimeTorrents" 
echo "- YTS (movies only)"
echo "- EZTV (TV shows)"
