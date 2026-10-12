# Torrents with Mullvad VPN

qBittorrent torrent client running through Mullvad VPN with kill switch protection.

## 🔐 Security Features

- ✅ **All torrent traffic routed through Mullvad VPN** (Swedish server)
- ✅ **Kill switch enabled** - if VPN drops, torrents stop
- ✅ **No IP leaks** - qBittorrent can only access internet through VPN
- ✅ **Local network access** - Web UI accessible from your LAN

## 📦 What's Included

- **Mullvad VPN** - WireGuard VPN container (se-got-wg-008 server in Gothenburg, Sweden)
- **qBittorrent** - Modern torrent client with web UI

Jackett and FlareSolverr (`jackett/`) share mullvad-vpn's network namespace, so recreating mullvad-vpn strands them. `scripts/netns-orphans.sh` recreates any container left in a dead namespace; the weekly updater and the medic's `netns` playbook run it (docker#165).

## 🚀 Quick Start

```bash
# Start the stack
docker compose up -d

# Check VPN is connected
docker exec mullvad-vpn curl -s https://am.i.mullvad.net/json | jq

# View logs
docker compose logs -f

# Stop the stack
docker compose down
```

## 🌐 Access

- **qBittorrent Web UI**: http://dockerhost:1337
- **Default credentials**: 
  - Username: `admin`
  - Password: Check logs with `docker logs qbittorrent | grep "temporary password"`

## 📁 Directories

- **Downloads**: `/mnt/boston/media/downloads/torrents` (7.3TB network storage)
- **Config**: `/home/brandon/torrents/config`
- **WireGuard Config**: `./se-got-wg-008.conf`

## 🔧 Configuration

Edit `.env` file to change:
- `WEBUI_PORT` - Web UI port (default: 1337)
- `DOWNLOAD_LOCATION` - Where torrents download to
- `CONFIG_LOCATION` - qBittorrent config directory

## ✅ Verify VPN is Working

```bash
# Check your real IP (from host)
curl -s https://api.ipify.org

# Check qBittorrent's IP (should be different - Mullvad IP)
docker exec qbittorrent curl -s https://api.ipify.org

# Check Mullvad connection status
docker exec mullvad-vpn curl -s https://am.i.mullvad.net/json | jq
```

Should show:
- `"mullvad_exit_ip": true`
- `"ip": "185.209.199.17"` (Mullvad Swedish server)

## 🛠️ Troubleshooting

**VPN not connecting:**
```bash
docker logs mullvad-vpn
```

**qBittorrent not accessible:**
```bash
# Check if containers are running
docker ps | grep -E 'mullvad|qbittorrent'

# Restart the stack
docker compose restart
```

**Get temporary password:**
```bash
docker logs qbittorrent 2>&1 | grep -A 2 "temporary password"
```

## 📊 Resource Usage

- **CPU**: Max 2 cores, reserved 0.5 cores
- **RAM**: Max 2GB, reserved 512MB

## 🔄 Updates

```bash
# Pull latest images
docker compose pull

# Restart with new images
docker compose up -d
```

## ⚠️ Important Notes

- **First run**: qBittorrent generates a random password - check logs!
- **VPN required**: If VPN container stops, qBittorrent loses internet access (by design)
- **Port forwarding**: Mullvad doesn't support port forwarding anymore (as of 2023)
- **Local network**: You can access the Web UI from your LAN (192.168.x.x)

## 🎯 Recommended qBittorrent Settings

After logging in, go to **Tools → Options**:

1. **Downloads**
   - Default save path: `/downloads`
   - Keep incomplete torrents in: `/downloads/incomplete`

2. **Connection**
   - Listening port: `6881` (already configured)
   - Use UPnP/NAT-PMP: ❌ Disabled (not needed with VPN)

3. **Speed**
   - Set upload/download limits as desired

4. **BitTorrent**
   - Enable DHT: ✅
   - Enable PEX: ✅
   - Enable Local Peer Discovery: ❌ (not useful with VPN)

5. **Web UI**
   - Change default password!
   - Enable "Bypass authentication for clients on localhost": ✅
   - Enable "Bypass authentication for clients in whitelisted IP subnets": Add `192.168.0.0/16`

