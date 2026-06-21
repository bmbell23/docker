# VPN Torrent Stack - Complete Documentation

**Last Updated:** 2026-06-03  
**Status:** ✅ Operational  
**Server:** Boston (Tailscale: 100.69.184.113)

---

## 📋 Overview

This document covers the complete VPN-based torrent stack running on Docker. All torrent-related traffic routes through Mullvad VPN for privacy and security.

### Stack Components

1. **Mullvad VPN** (WireGuard) - VPN gateway container
2. **qBittorrent** - Torrent client (routes through VPN)
3. **Jackett** - Torrent indexer aggregator (routes through VPN)
4. **FlareSolverr** - Cloudflare bypass service (routes through VPN)

---

## 🌐 Network Architecture

### How Traffic Routes

```
Internet ←→ Mullvad VPN Container (WireGuard) ←→ Dependent Containers
                     ↓
            - qBittorrent (network_mode: service:vpn)
            - Jackett (network_mode: container:mullvad-vpn)
            - FlareSolverr (network_mode: container:mullvad-vpn)
```

**Key Concept:** Containers using `network_mode: "container:X"` share the network namespace with container X. All traffic appears to come from the VPN.

### Current VPN Configuration

- **Provider:** Mullvad VPN
- **Protocol:** WireGuard
- **Server:** Gothenburg, Sweden (se-got-wg-003)
- **Endpoint:** 185.213.154.68:51820
- **Config File:** `/home/brandon/projects/docker/torrents/se-got-wg-003.conf`
- **VPN IP:** 185.213.154.185 (verify with: `docker exec mullvad-vpn curl https://ifconfig.me`)
- **VPN Network:** 10.72.183.133/32 (internal)

### DNS Configuration

**CRITICAL:** Mullvad blocks external DNS servers. You MUST use Mullvad's DNS.

- **Current DNS:** 100.64.0.63
- **Configured in:**
  - WireGuard config: `torrents/se-got-wg-003.conf` (line 5: `DNS = 100.64.0.63`)
  - Docker Compose: `torrents/docker-compose.yml` (line 21: `dns: - 100.64.0.63`)

**Why both?** WireGuard's `resolvconf` reads the DNS from the config file, and docker-compose DNS is a fallback.

---

## 🔧 Container Details

### 1. Mullvad VPN Container

**Container Name:** `mullvad-vpn`  
**Image:** `lscr.io/linuxserver/wireguard:latest`  
**Network:** `torrents_vpn_network` (172.32.0.0/16)  
**Exposed Ports:**
- 2285 → 8080 (qBittorrent Web UI)
- 9117 → 9117 (Jackett Web UI)
- 6881 → 6881 (TCP/UDP - qBittorrent connections)

**Config Location:** `/home/brandon/projects/docker/torrents/`

**Check VPN Status:**
```bash
# Check WireGuard tunnel
docker exec mullvad-vpn wg show

# Verify VPN IP
docker exec mullvad-vpn curl https://ifconfig.me

# Test DNS
docker exec mullvad-vpn nslookup google.com

# Check handshake (should be recent)
docker exec mullvad-vpn wg show wg0 transfer
```

### 2. qBittorrent Container

**Container Name:** `qbittorrent`  
**Image:** `lscr.io/linuxserver/qbittorrent:latest`  
**Network Mode:** `service:vpn` (shares VPN network)  
**Web UI:** http://100.69.184.113:2285 or http://127.0.0.1:2285

**Paths:**
- Config: `/home/brandon/torrents/config`
- Downloads: `/mnt/boston/media/downloads/torrents`
- Watch: `/home/brandon/projects/docker/torrents/watch`

**Environment (.env file):**
```
DOWNLOAD_LOCATION=/mnt/boston/media/downloads/torrents
CONFIG_LOCATION=/home/brandon/torrents/config
WEBUI_PORT=2285
TZ=America/New_York
PUID=1000
PGID=1000
```

### 3. Jackett Container

**Container Name:** `jackett`  
**Image:** `lscr.io/linuxserver/jackett:latest`  
**Network Mode:** `container:mullvad-vpn` (shares VPN network)  
**Web UI:** http://100.69.184.113:9117 or http://127.0.0.1:9117

**Paths:**
- Config: `/home/brandon/jackett/config`
- Downloads: `/mnt/boston/media/torrents`

**Port Exposure:** Port 9117 is exposed on the `mullvad-vpn` container, NOT on jackett directly.

**Environment (.env file):**
```
PUID=1000
PGID=1000
TZ=America/Denver
JACKETT_PORT=9117
CONFIG_LOCATION=/home/brandon/jackett/config
DOWNLOAD_LOCATION=/mnt/boston/media/torrents
```

### 4. FlareSolverr Container

**Container Name:** `flaresolverr`  
**Image:** `ghcr.io/flaresolverr/flaresolverr:latest`  
**Network Mode:** `container:mullvad-vpn` (shares VPN network)  
**Internal Port:** 8191 (accessed by Jackett)

**Purpose:** Bypasses Cloudflare protection on indexers like 1337x.

---

## 🚀 Common Operations

### Starting/Restarting Services

**⚠️ IMPORTANT:** Never use `docker compose down/restart` directly - they often fail with permission errors.

**Proper Restart Procedure:**

```bash
# 1. Kill container processes
sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | xargs -I {} sh -c 'sudo docker inspect {} 2>/dev/null | grep "\"Pid\"" | grep -o "[0-9]*" | xargs -I PID sudo kill -9 PID 2>/dev/null'

# 2. Remove containers
sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | xargs sudo docker rm -f

# 3. Restart VPN first
cd /home/brandon/projects/docker/torrents && sudo docker compose up -d

# 4. Wait 5 seconds for VPN to connect
sleep 5

# 5. Restart dependent services
cd /home/brandon/projects/docker/jackett && sudo docker compose up -d
```

**Why?** Docker sometimes has permission issues killing containers. Killing the process directly with `kill -9` bypasses this.

### Container Dependency Order

**Always restart in this order:**
1. `mullvad-vpn` (VPN gateway - MUST be first)
2. Wait 5 seconds (allow VPN to establish connection)
3. `qbittorrent` (depends on VPN service)
4. `jackett` and `flaresolverr` (depend on VPN container)

### Verifying Everything is Working

```bash
# Check all containers are running
docker ps | grep -E "mullvad|qbittorrent|jackett|flaresolverr"

# Verify VPN connection
docker exec mullvad-vpn wg show wg0 | grep "latest handshake"
# Should show a recent timestamp (< 2 minutes)

# Verify DNS works
docker exec mullvad-vpn nslookup google.com
# Should resolve successfully

# Verify Jackett uses VPN
docker exec jackett curl -s https://ifconfig.me
# Should show Mullvad IP (currently: 185.213.154.185)

# Verify qBittorrent uses VPN
docker exec qbittorrent curl -s https://ifconfig.me
# Should show same Mullvad IP

# Test web interfaces
curl -I http://127.0.0.1:9117  # Jackett
curl -I http://127.0.0.1:2285  # qBittorrent
```

---

## 🔒 Getting a New Mullvad VPN Config

**When you need a new config:**
- VPN endpoint is not responding (0 bytes received in `wg show`)
- Mullvad subscription renewed
- Want to switch servers/locations

**Steps:**

1. Go to https://mullvad.net/en/account/wireguard-config
2. Enter your Mullvad account number
3. Select:
   - **Platform:** Linux
   - **Country/City:** Sweden > Gothenburg (or any server)
   - **Server:** Pick available server (e.g., se-got-wg-003)
4. Click **"Generate key"**
5. Click **"Download file"**

6. Copy the file to the torrents directory:
```bash
cp ~/Downloads/se-got-wg-XXX.conf /home/brandon/projects/docker/torrents/
```

7. Update `docker-compose.yml`:
```bash
cd /home/brandon/projects/docker/torrents
# Edit docker-compose.yml:
# - Line 16: Change config file path to new .conf
# - Line 21: Update DNS to match the "DNS = " line in new .conf file
```

8. Restart services using the proper procedure above

**DNS Note:** The DNS server changes with each config. Always check the `DNS = ` line in the new .conf file and update docker-compose.yml to match.

---

## 🐛 Troubleshooting

### Issue: VPN not connecting (0 bytes received)

**Symptoms:**
```bash
docker exec mullvad-vpn wg show wg0 transfer
# Output: Vh3Y2LsBG1yN4kDeebOr3J6dFooGJIBTftzVqlWhiD4=  0  3700
#                                                      ↑ Zero bytes received = BAD
```

**Cause:** VPN endpoint is dead or config expired.

**Solution:** Get a new Mullvad config (see section above).

---

### Issue: DNS resolution fails (SERVFAIL)

**Symptoms:**
```bash
docker exec mullvad-vpn nslookup google.com
# Output: ;; connection timed out; no servers could be reached
```

**Cause:** Using wrong DNS server (Mullvad blocks external DNS like 8.8.8.8, 1.1.1.1).

**Solution:**
1. Check DNS in WireGuard config:
```bash
grep "DNS = " /home/brandon/projects/docker/torrents/se-got-wg-003.conf
# Should show: DNS = 100.64.0.63 (or another 100.64.x.x address)
```

2. Check DNS in docker-compose.yml:
```bash
grep -A 2 "dns:" /home/brandon/projects/docker/torrents/docker-compose.yml
# Should match the WireGuard config DNS
```

3. If mismatched, update docker-compose.yml and restart.

---

### Issue: Jackett/qBittorrent not accessible externally (Tailscale IP hangs)

**Symptoms:**
- `curl http://127.0.0.1:9117` works
- `curl http://100.69.184.113:9117` hangs/times out

**Cause:** Stale iptables DNAT rules from old Docker networks.

**Solution:**

1. Find the current Docker bridge:
```bash
docker network ls | grep vpn
# Note the network ID (e.g., e1a308310b0a)
```

2. Check for stale DNAT rules:
```bash
sudo iptables-save | grep "9117"
# Look for multiple DNAT rules with different bridge IDs
```

3. Remove stale rules (replace `br-XXXXXXXX` with old bridge):
```bash
sudo iptables -t nat -D DOCKER ! -i br-XXXXXXXX -p tcp -m tcp --dport 9117 -j DNAT --to-destination 172.32.0.2:9117
```

4. Also remove stale ACCEPT rules:
```bash
sudo iptables -D DOCKER ! -i br-XXXXXXXX -o br-XXXXXXXX -p tcp -m tcp --dport 9117 -j ACCEPT
```

---

### Issue: Container can't resolve domains but can ping IPs

**Symptoms:**
- `docker exec mullvad-vpn ping 8.8.8.8` works
- `docker exec mullvad-vpn curl https://google.com` fails

**Cause:** DNS is broken.

**Solution:** See "DNS resolution fails" above.

---

### Issue: VPN tunnel established but no internet access

**Symptoms:**
```bash
docker exec mullvad-vpn wg show
# Shows "latest handshake" but apps can't connect

docker exec mullvad-vpn curl https://ifconfig.me
# Times out or fails
```

**Diagnostic:**
```bash
# Check routing
docker exec mullvad-vpn ip route

# Check DNS
docker exec mullvad-vpn cat /etc/resolv.conf

# Test VPN endpoint reachability
ping 185.213.154.68
```

**Solution:** Usually a DNS issue. Verify DNS configuration matches VPN config file.

---

## 📊 Monitoring

### Quick Health Check Script

```bash
#!/bin/bash
echo "=== VPN Torrent Stack Health Check ==="
echo ""
echo "1. Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "mullvad|qbit|jackett|flare|Names"
echo ""
echo "2. VPN Connection:"
docker exec mullvad-vpn wg show wg0 | grep -E "latest handshake|transfer"
echo ""
echo "3. External IP (should be Mullvad):"
docker exec mullvad-vpn curl -s https://ifconfig.me
echo ""
echo "4. DNS Test:"
docker exec mullvad-vpn nslookup google.com | grep -A 1 "Server:"
echo ""
echo "5. Jackett VPN Test:"
docker exec jackett curl -s https://ifconfig.me
```

Save as `/home/brandon/projects/docker/health-check.sh` and run with `bash health-check.sh`.

---

## 📁 Important File Locations

### Configuration Files

| File | Path | Purpose |
|------|------|---------|
| VPN Config (Current) | `/home/brandon/projects/docker/torrents/se-got-wg-003.conf` | WireGuard config for Mullvad |
| VPN Config (Old) | `/home/brandon/projects/docker/torrents/se-got-wg-008.conf` | Previous config (inactive) |
| VPN Docker Compose | `/home/brandon/projects/docker/torrents/docker-compose.yml` | VPN + qBittorrent |
| Jackett Docker Compose | `/home/brandon/projects/docker/jackett/docker-compose.yml` | Jackett + FlareSolverr |
| VPN Environment | `/home/brandon/projects/docker/torrents/.env` | qBittorrent settings |
| Jackett Environment | `/home/brandon/projects/docker/jackett/.env` | Jackett settings |

### Data Directories

| Type | Path | Purpose |
|------|------|---------|
| qBittorrent Config | `/home/brandon/torrents/config` | qBittorrent settings |
| qBittorrent Downloads | `/mnt/boston/media/downloads/torrents` | Downloaded torrents |
| qBittorrent Watch | `/home/brandon/projects/docker/torrents/watch` | Auto-add .torrent files |
| Jackett Config | `/home/brandon/jackett/config` | Jackett settings |
| Jackett Downloads | `/mnt/boston/media/torrents` | Shared with qBittorrent |

---

## 🔐 Security Notes

1. **All torrent traffic uses VPN** - Verified by checking external IP from containers
2. **Kill switch** - If VPN dies, containers lose internet (they share VPN network)
3. **DNS leak protection** - Containers use Mullvad DNS only
4. **No WebRTC leaks** - Containers don't have browsers

### Verifying No Leaks

```bash
# Check that Jackett shows VPN IP
docker exec jackett curl -s https://ifconfig.me
# Should match: docker exec mullvad-vpn curl -s https://ifconfig.me

# Check DNS
docker exec jackett cat /etc/resolv.conf
# Should show: nameserver 100.64.0.63

# Check routing (should go through wg0)
docker exec mullvad-vpn ip route
```

---

## 🆘 Emergency Recovery

If everything is broken and you need to start fresh:

```bash
# 1. Stop and remove all containers
cd /home/brandon/projects/docker
sudo docker compose -f torrents/docker-compose.yml down
sudo docker compose -f jackett/docker-compose.yml down

# 2. Remove any stuck containers manually
sudo docker ps -a | grep -E "mullvad|qbit|jackett|flare" | awk '{print $1}' | xargs sudo docker rm -f

# 3. Clean up old networks (optional)
docker network prune -f

# 4. Restart VPN first
cd torrents && sudo docker compose up -d

# 5. Wait for VPN to connect
sleep 10

# 6. Check VPN is working
docker exec mullvad-vpn wg show
docker exec mullvad-vpn curl https://ifconfig.me

# 7. Start Jackett
cd ../jackett && sudo docker compose up -d

# 8. Verify all services
docker ps | grep -E "mullvad|qbit|jackett|flare"
```

---

## 📚 Additional Resources

- **Mullvad VPN:** https://mullvad.net
- **WireGuard Config Generator:** https://mullvad.net/en/account/wireguard-config
- **Jackett Documentation:** `/home/brandon/projects/docker/jackett/README.md`
- **qBittorrent Documentation:** `/home/brandon/projects/docker/torrents/README.md`
- **Docker Rules:** `/home/brandon/projects/docker/.augment/rules/docker-rules.md`

---

**Document Version:** 1.0
**Created:** 2026-06-03
**Author:** AI Assistant + Brandon
