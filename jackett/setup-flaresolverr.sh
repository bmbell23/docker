#!/bin/bash

# Setup script for Jackett + FlareSolverr configuration
# This script helps configure FlareSolverr and fix common indexer issues

echo "=== Jackett + FlareSolverr Setup ==="
echo

# Check if services are running
echo "1. Checking service status..."
docker-compose ps

echo
echo "2. Checking FlareSolverr connectivity (from inside container)..."
if docker-compose exec -T jackett curl -s http://127.0.0.1:8191 > /dev/null; then
    echo "✅ FlareSolverr is accessible from Jackett container"
else
    echo "❌ FlareSolverr is not accessible from Jackett container"
    exit 1
fi

echo
echo "3. Checking Jackett connectivity (from VPN network)..."
if docker-compose exec -T jackett curl -s http://127.0.0.1:9117 > /dev/null; then
    echo "✅ Jackett is accessible from within VPN network"
else
    echo "❌ Jackett is not accessible. Check if container is running."
    exit 1
fi

echo
echo "=== MANUAL CONFIGURATION REQUIRED ==="
echo
echo "Please complete these steps manually in the Jackett web UI:"
echo
echo "1. Open Jackett: http://100.123.154.40:9117"
echo "2. Click the wrench icon (Settings) in top right"
echo "3. Scroll to 'FlareSolverr' section"
echo "4. Set FlareSolverr URL to: http://127.0.0.1:8191"
echo "5. Click 'Save'"
echo
echo "6. Remove problematic indexers:"
echo "   - Delete 'The Pirate Bay' (if present)"
echo "   - Delete '1337x' (if present)"
echo
echo "7. Re-add indexers:"
echo "   - Click 'Add indexer'"
echo "   - Search for 'The Pirate Bay' and add it"
echo "   - Search for '1337x' and add it"
echo "   - Add alternatives: TorrentGalaxy, LimeTorrents, YTS"
echo
echo "8. Test each indexer:"
echo "   - Click wrench icon next to each indexer"
echo "   - Click 'Test' button"
echo "   - Should show 'Test successful'"
echo
echo "=== Alternative Indexers (if TPB/1337x still fail) ==="
echo "- TorrentGalaxy (very reliable)"
echo "- LimeTorrents (good alternative)"
echo "- YTS (movies only, high quality)"
echo "- EZTV (TV shows)"
echo "- Zooqle (general content)"
echo
echo "Setup complete! Check the logs if you encounter issues:"
echo "docker-compose logs --tail=50"
