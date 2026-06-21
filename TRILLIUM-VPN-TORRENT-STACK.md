# VPN Torrent Stack - Complete Reference

**Server:** Boston (Tailscale: 100.69.184.113) | **Status:** ✅ Operational | **Updated:** 2026-06-03

---

## Quick Access

| Service | Local URL | Tailscale URL |
|---------|-----------|---------------|
| **qBittorrent** | http://127.0.0.1:2285 | http://100.69.184.113:2285 |
| **Jackett** | http://127.0.0.1:9117 | http://100.69.184.113:9117 |

**Health Check:** `cd /home/brandon/projects/docker && bash health-check.sh`

---

## Current VPN Configuration

**VPN Details:**
- **Provider:** Mullvad VPN
- **Server:** se-got-wg-003 (Gothenburg, Sweden)
- **Endpoint:** 185.213.154.68:51820
- **VPN IP:** 185.213.154.185
- **DNS:** 100.64.0.63 (Mullvad DNS - CRITICAL!)
- **Config File:** `/home/brandon/projects/docker/torrents/se-got-wg-003.conf`

**Network:**
- **Docker Network:** torrents_vpn_network (172.32.0.0/16)
- **Tailscale IP:** 100.69.184.113

**Ports:**
- qBittorrent Web UI: 2285
- Jackett Web UI: 9117
- Torrent connections: 6881 (TCP/UDP)

---

## Network Architecture

```
Internet ←→ Mullvad VPN Container (WireGuard) ←→ Dependent Containers
                     ↓
            - qBittorrent (network_mode: service:vpn)
            - Jackett (network_mode: container:mullvad-vpn)
            - FlareSolverr (network_mode: container:mullvad-vpn)
```

**Key:** All containers share the VPN's network namespace → 100% traffic through VPN

---

## Quick Commands

### Health & Status
```bash
# Comprehensive health check
cd /home/brandon/projects/docker && bash health-check.sh

# Check VPN connection
docker exec mullvad-vpn wg show

# Verify VPN IP
docker exec mullvad-vpn curl https://ifconfig.me

# Test DNS
docker exec mullvad-vpn nslookup google.com

# Verify all services use VPN (should all show same IP)
docker exec mullvad-vpn curl -s https://ifconfig.me
docker exec jackett curl -s https://ifconfig.me
docker exec qbittorrent curl -s https://ifconfig.me
```

### View Logs
```bash
docker logs mullvad-vpn --tail 50
docker logs qbittorrent --tail 50
docker logs jackett --tail 50
docker logs flaresolverr --tail 50
```

### Container Status
```bash
docker ps | grep -E "mullvad|qbit|jackett|flare"
```

---

## Restart Services (PROPER METHOD)

**⚠️ NEVER use `docker compose restart` - it fails with permission errors**

**Always use this procedure:**

```bash
cd /home/brandon/projects/docker

# 1. Kill container processes
sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | \
  xargs -I {} sh -c 'sudo docker inspect {} 2>/dev/null | grep "\"Pid\"" | \
  grep -o "[0-9]*" | xargs -I PID sudo kill -9 PID 2>/dev/null'

# 2. Remove containers
sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | \
  xargs sudo docker rm -f

# 3. Start VPN first
cd torrents && sudo docker compose up -d

# 4. Wait for VPN to connect
sleep 5

# 5. Start Jackett & FlareSolverr
cd ../jackett && sudo docker compose up -d

# 6. Verify
docker ps | grep -E "mullvad|qbit|jackett|flare"
```

**Why this method?** Docker sometimes can't kill containers even with sudo. Direct `kill -9` on the PID bypasses this issue.

---

## DNS Configuration (CRITICAL!)

**Mullvad blocks external DNS servers (8.8.8.8, 1.1.1.1, etc.)**

DNS must be configured in **TWO places:**

1. **WireGuard Config** (`torrents/se-got-wg-003.conf`):
   ```
   DNS = 100.64.0.63
   ```

2. **Docker Compose** (`torrents/docker-compose.yml`):
   ```yaml
   dns:
     - 100.64.0.63
   ```

**Verify DNS is working:**
```bash
# Check DNS config
docker exec mullvad-vpn cat /etc/resolv.conf
# Should show: nameserver 100.64.0.63

# Test DNS resolution
docker exec mullvad-vpn nslookup google.com
# Should resolve successfully
```

---

## Getting a New Mullvad VPN Config

**When needed:**
- VPN endpoint not responding (0 bytes received in `wg show`)
- Subscription renewed
- Want to switch servers

**Steps:**

1. Visit: https://mullvad.net/en/account/wireguard-config
2. Enter Mullvad account number
3. Select:
   - **Platform:** Linux
   - **Country/City:** Sweden > Gothenburg (or any)
   - **Server:** Pick available (e.g., se-got-wg-003)
4. Click **"Generate key"**
5. Click **"Download file"**

6. Copy to server:
```bash
cp ~/Downloads/se-got-wg-XXX.conf /home/brandon/projects/docker/torrents/
```

7. Update `torrents/docker-compose.yml`:
   - Line 16: Change to new .conf filename
   - Line 21: Update DNS to match `DNS =` line in new .conf

8. Restart services (use proper method above)

**Important:** DNS server changes with each config! Always verify and update.

---

## Common Issues & Troubleshooting

### Issue: VPN not connecting (0 bytes received)

**Symptoms:**
```bash
docker exec mullvad-vpn wg show wg0 transfer
# Shows: 0 bytes received
```

**Cause:** VPN endpoint dead or config expired

**Fix:** Get new Mullvad config (see above)

---

### Issue: DNS resolution fails

**Symptoms:**
```bash
docker exec mullvad-vpn nslookup google.com
# Error: connection timed out; no servers could be reached
```

**Cause:** Using wrong DNS (Mullvad blocks external DNS)

**Fix:**
```bash
# Check DNS in config file
grep "DNS = " torrents/se-got-wg-003.conf

# Check DNS in docker-compose
grep -A 2 "dns:" torrents/docker-compose.yml

# If mismatched, update docker-compose.yml to match config file
# Then restart services
```

---

### Issue: Containers can ping IPs but not resolve domains

**Cause:** DNS broken

**Fix:** Verify DNS configuration (see DNS section above)

---

### Issue: Jackett/qBittorrent not accessible externally (Tailscale hangs)

**Symptoms:**
- `curl http://127.0.0.1:9117` works
- `curl http://100.69.184.113:9117` hangs

**Cause:** Stale iptables DNAT rules from old Docker networks

**Fix:**
```bash
# Find current network
docker network ls | grep vpn
# Note the ID (e.g., e1a308310b0a)

# Check for stale rules
sudo iptables-save | grep "9117"
# Look for rules with different bridge IDs (br-XXXXXXXX)

# Remove stale DNAT rule (replace br-OLDBRIDGE)
sudo iptables -t nat -D DOCKER ! -i br-OLDBRIDGE -p tcp -m tcp \
  --dport 9117 -j DNAT --to-destination 172.32.0.2:9117

# Remove stale ACCEPT rule
sudo iptables -D DOCKER ! -i br-OLDBRIDGE -o br-OLDBRIDGE -p tcp -m tcp \
  --dport 9117 -j ACCEPT
```

---

### Issue: VPN connected but no internet

**Diagnostics:**
```bash
# Check WireGuard status
docker exec mullvad-vpn wg show

# Check routing
docker exec mullvad-vpn ip route

# Check DNS
docker exec mullvad-vpn cat /etc/resolv.conf

# Test VPN endpoint from host
ping 185.213.154.68
```

**Usually:** DNS issue. Verify DNS matches config file.

---

## Container Details

### Mullvad VPN Container

**Name:** `mullvad-vpn`
**Image:** `lscr.io/linuxserver/wireguard:latest`
**Network:** torrents_vpn_network (172.32.0.0/16)
**Exposed Ports:**
- 2285 → 8080 (qBittorrent)
- 9117 → 9117 (Jackett)
- 6881 → 6881 (Torrents)

### qBittorrent Container

**Name:** `qbittorrent`
**Image:** `lscr.io/linuxserver/qbittorrent:latest`
**Network Mode:** `service:vpn` (shares VPN network)
**Config:** `/home/brandon/torrents/config`
**Downloads:** `/mnt/boston/media/downloads/torrents`

### Jackett Container

**Name:** `jackett`
**Image:** `lscr.io/linuxserver/jackett:latest`
**Network Mode:** `container:mullvad-vpn` (shares VPN network)
**Config:** `/home/brandon/jackett/config`
**Downloads:** `/mnt/boston/media/torrents`

**Note:** Port 9117 exposed on mullvad-vpn, not jackett directly

### FlareSolverr Container

**Name:** `flaresolverr`
**Image:** `ghcr.io/flaresolverr/flaresolverr:latest`
**Network Mode:** `container:mullvad-vpn`
**Port:** 8191 (internal - used by Jackett)
**Purpose:** Bypasses Cloudflare on indexers

---

## File Locations

### Config Files
```
/home/brandon/projects/docker/
├── torrents/
│   ├── docker-compose.yml          # VPN + qBittorrent
│   ├── .env                        # qBittorrent settings
│   ├── se-got-wg-003.conf         # Current VPN config ✅
│   └── se-got-wg-008.conf         # Old VPN config
├── jackett/
│   ├── docker-compose.yml          # Jackett + FlareSolverr
│   └── .env                        # Jackett settings
```

### Data Directories
```
/home/brandon/torrents/config                  # qBittorrent config
/home/brandon/jackett/config                   # Jackett config
/mnt/boston/media/downloads/torrents          # qBittorrent downloads
/mnt/boston/media/torrents                    # Jackett shared
```

### Documentation
```
/home/brandon/projects/docker/
├── VPN-README.md                   # Overview & quick start
├── VPN-QUICK-REFERENCE.md         # Quick commands
├── VPN-TORRENT-SETUP.md           # Complete documentation
├── health-check.sh                 # Health monitoring script
└── TRILLIUM-VPN-TORRENT-STACK.md  # This file (for Trillium)
```

---

## Security Verification

**All torrent traffic uses VPN:**
```bash
# All should show same Mullvad IP
docker exec mullvad-vpn curl -s https://ifconfig.me
docker exec jackett curl -s https://ifconfig.me
docker exec qbittorrent curl -s https://ifconfig.me
```

**DNS leak protection:**
```bash
# Should show Mullvad DNS
docker exec jackett cat /etc/resolv.conf
# nameserver 100.64.0.63
```

**Kill switch:** If VPN dies, containers lose internet (they share VPN network)

---

## Emergency Recovery

If everything is broken:

```bash
cd /home/brandon/projects/docker

# Stop everything
sudo docker compose -f torrents/docker-compose.yml down
sudo docker compose -f jackett/docker-compose.yml down

# Remove stuck containers
sudo docker ps -a | grep -E "mullvad|qbit|jackett|flare" | \
  awk '{print $1}' | xargs sudo docker rm -f

# Clean networks (optional)
docker network prune -f

# Restart VPN
cd torrents && sudo docker compose up -d && sleep 10

# Verify VPN
docker exec mullvad-vpn wg show
docker exec mullvad-vpn curl https://ifconfig.me

# Start Jackett
cd ../jackett && sudo docker compose up -d

# Verify all
docker ps | grep -E "mullvad|qbit|jackett|flare"
```

---

## Recent Changes (2026-06-03)

1. ✅ Updated Mullvad VPN config: se-got-wg-008 → se-got-wg-003
2. ✅ Updated DNS: 10.64.0.1 → 100.64.0.63 (matches new VPN)
3. ✅ Verified VPN connection working (handshake, data transfer)
4. ✅ Verified all services route through VPN (same IP)
5. ✅ Fixed Jackett downtime (VPN endpoint was dead)
6. ✅ Created comprehensive documentation
7. ✅ Created health monitoring script

---

## Additional Resources

- **Mullvad Account:** https://mullvad.net/en/account
- **WireGuard Config Generator:** https://mullvad.net/en/account/wireguard-config
- **Full Documentation:** See VPN-TORRENT-SETUP.md
- **Docker Rules:** `/home/brandon/projects/docker/.augment/rules/docker-rules.md`

---

**Document Version:** 1.0 (Trillium Edition)
**Created:** 2026-06-03
**Status:** All systems operational ✅
