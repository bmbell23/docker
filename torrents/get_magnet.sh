#!/bin/bash

# Get magnet links through VPN
# Usage: ./get_magnet.sh <torrent_site_url>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <url>"
    echo "Example: $0 'https://example.com/torrent-page'"
    echo "This will fetch the page through VPN and extract magnet links"
    exit 1
fi

URL="$1"
CONTAINER_NAME="mullvad-vpn"

echo "🔒 Fetching through VPN: $URL"
echo

# Check VPN first
VPN_STATUS=$(docker exec $CONTAINER_NAME curl -s https://am.i.mullvad.net/connected)
if ! echo "$VPN_STATUS" | grep -q "You are connected"; then
    echo "❌ VPN NOT CONNECTED - ABORTING FOR SAFETY"
    exit 1
fi

echo "✅ VPN Connected - Fetching page..."

# Fetch page through VPN and extract magnet links
docker exec $CONTAINER_NAME curl -s "$URL" | grep -o 'magnet:[^"]*' | head -5

echo
echo "💡 Copy any magnet link above and use:"
echo "💡 ./add_torrent.sh 'magnet:?xt=urn:btih:...'"
