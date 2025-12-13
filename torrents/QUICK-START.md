# 🚀 Quick Start Guide

## ✅ Setup Complete!

Your Mullvad VPN + qBittorrent torrent stack is now running!

### 🔐 VPN Status
- **Connected to:** Mullvad (Sweden - Gothenburg)
- **Your IP:** 185.209.199.153
- **Kill switch:** ENABLED ✅
- **All torrent traffic is routed through VPN**

### 🌐 Access qBittorrent

**Web UI:** http://dockerhost:1337

**Login Credentials:**
- Username: `admin`
- Password: `wphyn44sk`

⚠️ **IMPORTANT:** Change this password immediately after logging in!

### 📁 Downloads Location

All torrents download to: `/mnt/boston/media/downloads/torrents`

### 🔧 First Steps After Login

1. **Change Password:**
   - Go to **Tools → Options → Web UI**
   - Change the password under "Authentication"

2. **Configure Downloads:**
   - Go to **Tools → Options → Downloads**
   - Default save path is already set to `/downloads`
   - Optionally set incomplete torrents path to `/downloads/incomplete`

3. **Verify VPN:**
   - Add a torrent
   - Check your IP at https://ipleak.net/ from within qBittorrent
   - Should show Swedish IP (185.209.199.153)

### 🛠️ Useful Commands

```bash
# Check VPN status
docker exec mullvad-vpn curl -s https://am.i.mullvad.net/json | jq

# View logs
docker logs mullvad-vpn
docker logs qbittorrent

# Restart containers
cd /home/brandon/projects/docker/torrents
docker compose restart

# Stop containers
docker compose down

# Start containers
docker compose up -d
```

### ✅ Security Features

- ✅ All torrent traffic forced through VPN
- ✅ Kill switch enabled (if VPN drops, torrents stop)
- ✅ No IP leaks
- ✅ Local network access for Web UI
- ✅ Swedish server for privacy

### 📊 Resource Limits

- **CPU:** Max 2 cores
- **RAM:** Max 2GB

### 🎯 Next Steps

1. Log in to qBittorrent at http://dockerhost:1337
2. Change the default password
3. Start downloading! 🎵

For more details, see `README.md`

