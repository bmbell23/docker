# VPN Torrent Stack - Quick Reference Card

**Server:** Boston (100.69.184.113) | **Status:** ✅ Operational | **Last Config Update:** 2026-06-03

---

## 🔗 Quick Links

| Service | Local URL | Tailscale URL | Status |
|---------|-----------|---------------|--------|
| **qBittorrent** | http://127.0.0.1:2285 | http://100.69.184.113:2285 | ✅ |
| **Jackett** | http://127.0.0.1:9117 | http://100.69.184.113:9117 | ✅ |
| **FlareSolverr** | http://127.0.0.1:8191 | (internal only) | ✅ |

---

## ⚡ Quick Commands

### Health Check
```bash
cd /home/brandon/projects/docker && bash health-check.sh
```

### View Logs
```bash
docker logs mullvad-vpn --tail 50     # VPN logs
docker logs qbittorrent --tail 50     # qBittorrent logs
docker logs jackett --tail 50         # Jackett logs
docker logs flaresolverr --tail 50    # FlareSolverr logs
```

### Check VPN Status
```bash
docker exec mullvad-vpn wg show                    # Full WireGuard status
docker exec mullvad-vpn curl https://ifconfig.me   # Check VPN IP
docker exec mullvad-vpn nslookup google.com        # Test DNS
```

### Verify VPN is Being Used
```bash
# All should show the SAME Mullvad IP
docker exec mullvad-vpn curl -s https://ifconfig.me
docker exec jackett curl -s https://ifconfig.me
docker exec qbittorrent curl -s https://ifconfig.me
```

---

## 🔄 Restart Services (Proper Method)

**⚠️ Always use this method - never use `docker compose restart`**

```bash
# Full restart script
cd /home/brandon/projects/docker

# 1. Kill processes
sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | xargs -I {} sh -c 'sudo docker inspect {} 2>/dev/null | grep "\"Pid\"" | grep -o "[0-9]*" | xargs -I PID sudo kill -9 PID 2>/dev/null'

# 2. Remove containers
sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | xargs sudo docker rm -f

# 3. Start VPN
cd torrents && sudo docker compose up -d

# 4. Wait for VPN
sleep 5

# 5. Start Jackett
cd ../jackett && sudo docker compose up -d
```

---

## 🆘 Common Issues

### VPN Not Connecting (0 bytes received)
**Quick Fix:** Get new Mullvad config
1. Visit: https://mullvad.net/en/account/wireguard-config
2. Download new config → `/mnt/boston/media/downloads/`
3. Update `torrents/docker-compose.yml` (lines 16 & 21)
4. Restart services

### DNS Not Working
**Quick Check:**
```bash
docker exec mullvad-vpn cat /etc/resolv.conf
# Should show: nameserver 100.64.0.63 (or similar 100.64.x.x)
```

**Quick Fix:** Verify DNS in config file matches docker-compose.yml

### Jackett/qBittorrent Not Accessible Externally
**Quick Fix:** Remove stale iptables rules
```bash
sudo iptables-save | grep "9117"  # Check for duplicate rules
# If found, see VPN-TORRENT-SETUP.md for removal commands
```

---

## 📊 Current Configuration

| Setting | Value |
|---------|-------|
| **VPN Provider** | Mullvad |
| **VPN Server** | Gothenburg, Sweden (se-got-wg-003) |
| **VPN Endpoint** | 185.213.154.68:51820 |
| **VPN IP** | 185.213.154.185 |
| **DNS Server** | 100.64.0.63 |
| **Docker Network** | torrents_vpn_network (172.32.0.0/16) |
| **qBittorrent Port** | 2285 |
| **Jackett Port** | 9117 |
| **Torrent Port** | 6881 (TCP/UDP) |

---

## 📁 Key File Locations

```
/home/brandon/projects/docker/
├── torrents/
│   ├── docker-compose.yml          # VPN + qBittorrent config
│   ├── .env                        # qBittorrent environment
│   ├── se-got-wg-003.conf         # Current VPN config ✅
│   └── se-got-wg-008.conf         # Old VPN config
├── jackett/
│   ├── docker-compose.yml          # Jackett + FlareSolverr config
│   └── .env                        # Jackett environment
├── health-check.sh                 # Health check script
├── VPN-TORRENT-SETUP.md           # Full documentation
└── VPN-QUICK-REFERENCE.md         # This file

Data Directories:
/home/brandon/torrents/config                  # qBittorrent config
/home/brandon/jackett/config                   # Jackett config
/mnt/boston/media/downloads/torrents          # qBittorrent downloads
/mnt/boston/media/torrents                    # Jackett downloads
```

---

## 🔍 Diagnostic Commands

```bash
# Check all containers are running
docker ps | grep -E "mullvad|qbit|jackett|flare"

# Check VPN handshake (should be < 2 minutes ago)
docker exec mullvad-vpn wg show wg0 | grep "latest handshake"

# Check data transfer (received should be > 0)
docker exec mullvad-vpn wg show wg0 | grep "transfer"

# Test DNS resolution
docker exec mullvad-vpn nslookup google.com

# Check container IPs
docker inspect mullvad-vpn | grep IPAddress

# Check exposed ports
docker port mullvad-vpn

# Check iptables NAT rules for port 9117
sudo iptables -t nat -L DOCKER -n | grep 9117
```

---

## 📞 When to Read Full Docs

Read **VPN-TORRENT-SETUP.md** for:
- Detailed network architecture
- Step-by-step troubleshooting
- How to configure new VPN server
- Understanding container dependencies
- Security verification
- Emergency recovery procedures

---

**Quick Reference Version:** 1.0  
**Last Updated:** 2026-06-03
