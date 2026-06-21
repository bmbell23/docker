# VPN Torrent Stack Documentation

**Last Updated:** 2026-06-03  
**Status:** ✅ All systems operational

---

## 📚 Documentation Overview

This folder contains complete documentation for the VPN-based torrent stack running on the Boston server.

### Available Documents

1. **[VPN-QUICK-REFERENCE.md](VPN-QUICK-REFERENCE.md)** - Start here!
   - Quick commands and URLs
   - Common troubleshooting steps
   - Current configuration snapshot
   - Perfect for day-to-day operations

2. **[VPN-TORRENT-SETUP.md](VPN-TORRENT-SETUP.md)** - Complete documentation
   - Network architecture explained
   - Detailed troubleshooting guide
   - How to update VPN configuration
   - Emergency recovery procedures
   - Security verification steps

3. **[health-check.sh](health-check.sh)** - Health monitoring script
   - Automated health checks
   - Verifies all components
   - Run with: `bash health-check.sh`

---

## 🚀 Quick Start

### Check if everything is working
```bash
cd /home/brandon/projects/docker
bash health-check.sh
```

### Access the services
- **Jackett:** http://127.0.0.1:9117 or http://100.69.184.113:9117
- **qBittorrent:** http://127.0.0.1:2285 or http://100.69.184.113:2285

### Restart everything (if needed)
```bash
cd /home/brandon/projects/docker

# Kill and remove containers
sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | xargs -I {} sh -c 'sudo docker inspect {} 2>/dev/null | grep "\"Pid\"" | grep -o "[0-9]*" | xargs -I PID sudo kill -9 PID 2>/dev/null'
sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | xargs sudo docker rm -f

# Restart VPN first
cd torrents && sudo docker compose up -d && sleep 5

# Then start Jackett
cd ../jackett && sudo docker compose up -d
```

---

## 📋 What's Included

### Services Running

1. **Mullvad VPN** (WireGuard)
   - VPN gateway for all torrent traffic
   - Current server: Gothenburg, Sweden (se-got-wg-003)
   - External IP: 185.213.154.185

2. **qBittorrent**
   - Torrent client
   - All traffic routes through VPN
   - Web UI on port 2285

3. **Jackett**
   - Torrent indexer aggregator
   - All traffic routes through VPN
   - Web UI on port 9117

4. **FlareSolverr**
   - Cloudflare bypass service
   - Used by Jackett for protected indexers
   - Internal only (port 8191)

### How It Works

```
Internet ←→ Mullvad VPN Container ←→ Dependent Containers
                    ↓
           [qBittorrent]
           [Jackett]
           [FlareSolverr]
```

All containers share the VPN's network namespace, ensuring 100% of torrent traffic goes through the VPN.

---

## 🔐 Security Features

✅ **VPN Kill Switch** - If VPN dies, containers lose internet  
✅ **DNS Leak Protection** - Containers use only Mullvad DNS (100.64.0.63)  
✅ **IP Verification** - All containers show same Mullvad IP  
✅ **No WebRTC Leaks** - Containers don't have browsers  

### Verify Security

```bash
# All three should show the SAME Mullvad IP
docker exec mullvad-vpn curl -s https://ifconfig.me
docker exec jackett curl -s https://ifconfig.me
docker exec qbittorrent curl -s https://ifconfig.me
```

---

## 🆘 Common Issues

| Problem | Quick Fix | Details |
|---------|-----------|---------|
| VPN not connecting | Get new Mullvad config | See VPN-TORRENT-SETUP.md |
| DNS not working | Check DNS matches config file | See VPN-QUICK-REFERENCE.md |
| Can't access externally | Remove stale iptables rules | See VPN-TORRENT-SETUP.md |
| Containers not starting | Use proper restart procedure | See VPN-QUICK-REFERENCE.md |

---

## 📊 Current Configuration Snapshot

**VPN Details:**
- Provider: Mullvad
- Server: se-got-wg-003 (Gothenburg, Sweden)
- Endpoint: 185.213.154.68:51820
- DNS: 100.64.0.63
- Config: `/home/brandon/projects/docker/torrents/se-got-wg-003.conf`

**Network:**
- Docker Network: torrents_vpn_network (172.32.0.0/16)
- Tailscale IP: 100.69.184.113

**Ports:**
- qBittorrent Web UI: 2285
- Jackett Web UI: 9117
- Torrent connections: 6881 (TCP/UDP)

---

## 📁 File Locations

**Docker Configs:**
```
/home/brandon/projects/docker/
├── torrents/docker-compose.yml    # VPN + qBittorrent
├── jackett/docker-compose.yml     # Jackett + FlareSolverr
```

**Data Storage:**
```
/home/brandon/torrents/config              # qBittorrent config
/home/brandon/jackett/config               # Jackett config
/mnt/boston/media/downloads/torrents       # qBittorrent downloads
```

---

## 🔄 Recent Changes (2026-06-03)

1. ✅ Updated Mullvad VPN config from se-got-wg-008 to se-got-wg-003
2. ✅ Updated DNS server to 100.64.0.63 (matches new VPN config)
3. ✅ Verified VPN connection is working (handshake active, data flowing)
4. ✅ Verified all services route through VPN
5. ✅ Created comprehensive documentation
6. ✅ Created health check script

---

## 💡 Best Practices

1. **Always check VPN first** - If services aren't working, check VPN is connected
2. **Use health check script** - Run `bash health-check.sh` regularly
3. **Follow restart procedure** - Never use `docker compose restart` directly
4. **Keep configs backed up** - VPN configs are in the torrents/ directory
5. **Monitor VPN handshake** - Should be < 2 minutes old

---

## 🔗 External Resources

- **Mullvad Account:** https://mullvad.net/en/account
- **Generate WireGuard Config:** https://mullvad.net/en/account/wireguard-config
- **Docker Project Rules:** `/home/brandon/projects/docker/.augment/rules/docker-rules.md`

---

## 📞 Need Help?

1. **Check health status:** Run `bash health-check.sh`
2. **Check quick reference:** See [VPN-QUICK-REFERENCE.md](VPN-QUICK-REFERENCE.md)
3. **Check full docs:** See [VPN-TORRENT-SETUP.md](VPN-TORRENT-SETUP.md)
4. **Check container logs:** `docker logs [container-name] --tail 50`

---

**Documentation maintained by:** AI Assistant + Brandon  
**Version:** 1.0  
**Created:** 2026-06-03
