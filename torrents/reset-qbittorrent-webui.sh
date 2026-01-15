#!/bin/bash
# Reset qBittorrent WebUI credentials and clear ban list

echo "🔧 Resetting qBittorrent WebUI..."

# Stop qBittorrent (keep trying different methods)
echo "Stopping qBittorrent container..."
docker exec qbittorrent pkill -9 qbittorrent-nox
sleep 2

# Backup current config
echo "Backing up config..."
cp /home/brandon/torrents/config/qBittorrent/qBittorrent.conf /home/brandon/torrents/config/qBittorrent/qBittorrent.conf.backup.$(date +%Y%m%d_%H%M%S)

# Remove username and password from config
echo "Removing WebUI credentials..."
sed -i '/WebUI\\Username=/d' /home/brandon/torrents/config/qBittorrent/qBittorrent.conf
sed -i '/WebUI\\Password_PBKDF2=/d' /home/brandon/torrents/config/qBittorrent/qBittorrent.conf

# Clear any ban list
echo "Clearing ban list..."
sed -i '/WebUI\\BanList=/d' /home/brandon/torrents/config/qBittorrent/qBittorrent.conf

# Restart qBittorrent process inside container
echo "Restarting qBittorrent..."
docker exec qbittorrent s6-svc -r /run/service/svc-qbittorrent

# Wait for it to start
echo "Waiting for qBittorrent to start..."
sleep 5

# Get the new temporary password
echo ""
echo "✅ Reset complete!"
echo ""
echo "New credentials:"
docker logs qbittorrent 2>&1 | grep -A 2 "temporary password" | tail -3
echo ""
echo "🌐 Access at: http://localhost:2285"
echo ""
echo "⚠️  IMPORTANT: Clear your browser cache and cookies for localhost:2285 before trying to login!"
echo ""

