#!/bin/bash

# VPN-protected torrent search script
# All requests go through the Mullvad VPN

CONTAINER_NAME="mullvad-vpn"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <search_term>"
    echo "Example: $0 'ubuntu 22.04'"
    echo "Example: $0 'creative commons music'"
    exit 1
fi

SEARCH_TERM="$1"
echo "🔒 Searching through VPN for: $SEARCH_TERM"
echo

# Check VPN status first
echo "Checking VPN connection..."
VPN_STATUS=$(docker exec $CONTAINER_NAME curl -s https://am.i.mullvad.net/connected)
if echo "$VPN_STATUS" | grep -q "You are connected"; then
    echo "✅ VPN Connected - Safe to search"
    VPN_INFO=$(docker exec $CONTAINER_NAME curl -s https://am.i.mullvad.net/json)
    echo "📍 Location: $(echo $VPN_INFO | grep -o '"country":"[^"]*"' | cut -d'"' -f4)"
    echo
else
    echo "❌ VPN NOT CONNECTED - ABORTING FOR SAFETY"
    exit 1
fi

# Search legal torrent sites through VPN
echo "🔍 Searching legal torrent sources..."
echo

# Internet Archive (legal torrents)
echo "--- Internet Archive ---"
docker exec $CONTAINER_NAME curl -s "https://archive.org/advancedsearch.php?q=${SEARCH_TERM// /+}+AND+mediatype:software&fl=identifier,title,description&rows=5&output=json" | \
    grep -o '"identifier":"[^"]*"' | head -3

echo

# You can add more legal torrent sources here
echo "💡 To get magnet links, visit these sites through your VPN-protected browser"
echo "💡 Or use: docker exec mullvad-vpn curl -s 'URL' to fetch specific pages"
