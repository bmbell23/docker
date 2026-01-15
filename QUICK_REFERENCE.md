# Quick Reference - Docker Services

## 🚨 If Services Are Not Accessible

### Quick Fix (Run This)
```bash
cd ~/projects/docker
sudo ./scripts/fix-all-docker-iptables.sh
```

This fixes all 18 services on your homepage in one command.

## 📋 Service URLs (Tailscale)

### Media & Entertainment
- **Jellyfin**: http://100.123.154.40:8096
- **Audiobookshelf**: http://100.123.154.40:13378
- **Navidrome**: http://100.123.154.40:4533
- **Romm**: http://100.123.154.40:8082

### Books
- **GreatReads (Prod)**: http://100.123.154.40:8007
- **GreatReads (Dev)**: http://100.123.154.40:8008
- **Kavita**: http://100.123.154.40:5000

### Forge Apps
- **LifeForge**: http://100.123.154.40:8004
- **ArtForge**: http://100.123.154.40:8003
- **WordForge**: http://100.123.154.40:8002
- **CodeForge**: http://100.123.154.40:8009

### Photos
- **Immich**: http://100.123.154.40:2283

### Downloads
- **qBittorrent**: http://100.123.154.40:2285
- **Jackett**: http://100.123.154.40:9117
- **YT-DLP Web**: http://100.123.154.40:8998

### Other
- **Dashboard**: http://100.123.154.40:8001
- **Picard**: http://100.123.154.40:5800
- **Beets**: http://100.123.154.40:8337

## 🔧 Common Commands

### Check if a service is accessible
```bash
curl -I http://192.168.0.158:PORT
```

### View container logs
```bash
docker logs CONTAINER_NAME --tail 50
```

### Restart a container
```bash
cd ~/projects/docker/FOLDER
docker compose restart
```

### Check iptables rules
```bash
sudo iptables -t nat -L DOCKER -n | grep PORT
```

### Check systemd service status
```bash
sudo systemctl status docker-iptables.service
```

## 🔄 After Server Reboot

The systemd service will automatically fix iptables rules 30 seconds after Docker starts.

To verify:
```bash
sudo systemctl status docker-iptables.service
journalctl -u docker-iptables.service
```

## 📁 Important Files

### Scripts
- `scripts/fix-all-docker-iptables.sh` - Fix all services
- `scripts/docker-iptables.service` - Systemd service

### Documentation
- `SOLUTION_SUMMARY.md` - Complete solution overview
- `DOCKER_IPTABLES_PERSISTENCE.md` - Detailed persistence guide
- `IMMICH_SETUP.md` - Immich user setup
- `DOCKER_IPTABLES_FIX.md` - Original fix documentation

## ⚠️ Immich First-Time Setup

Immich needs initial user creation:

1. Go to http://100.123.154.40:2283
2. Complete the setup wizard
3. Create admin user
4. See `IMMICH_SETUP.md` for details

## 🐛 Troubleshooting

### Service not accessible
1. Check if container is running: `docker ps | grep CONTAINER`
2. Check logs: `docker logs CONTAINER_NAME`
3. Run fix script: `sudo ./scripts/fix-all-docker-iptables.sh`

### After Docker restart
Services may become inaccessible. Run:
```bash
sudo ./scripts/fix-all-docker-iptables.sh
```

### Container IP changed
1. Find new IP: `docker inspect CONTAINER --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'`
2. Update `scripts/fix-all-docker-iptables.sh`
3. Re-run the script

## 📊 Service Status Check

Quick check all services:
```bash
for port in 2283 8096 8082 8004 8003 8002 8009 8007 8008 13378 2285 9117 8998; do 
  echo -n "Port $port: "
  curl -I http://192.168.0.158:$port --max-time 2 2>&1 | grep -E "HTTP|curl:" | head -1
done
```

## 🔐 Default Credentials

Most services require initial setup. Check individual service documentation.

**Immich**: No users exist - needs initial setup via web UI

## 📞 Getting Help

1. Check logs: `docker logs CONTAINER_NAME`
2. Check documentation in this folder
3. Verify iptables rules are present
4. Re-run fix script if needed

