#!/bin/bash

# qBittorrent status checking script

CONTAINER_NAME="qbittorrent"

echo "=== qBittorrent Status ==="
echo

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo "❌ qBittorrent container is not running!"
    exit 1
fi

echo "✅ qBittorrent container is running"
echo

# Check VPN connection
echo "🔒 VPN Status:"
docker exec mullvad-vpn curl -s https://am.i.mullvad.net/connected | grep -q "You are connected" && echo "✅ VPN Connected" || echo "❌ VPN Disconnected"
echo

# Check downloads directory
echo "📁 Downloads directory:"
ls -la /home/brandon/downloads/ | head -10
echo

# Check watch folder
echo "👀 Watch folder:"
ls -la /home/brandon/projects/docker/torrents/watch/
echo

# Check container logs for any errors
echo "📋 Recent container logs:"
docker logs $CONTAINER_NAME --tail 10
echo

# Try to get torrent info (if API works)
echo "🌐 Attempting to get torrent info via API:"
curl -s --connect-timeout 2 http://localhost:2285/api/v2/torrents/info | head -100
echo
