# Docker iptables Persistence Solution

## Problem
Docker's iptables rules are not persistent across:
- Server reboots
- Docker daemon restarts
- Container restarts (in some cases)

This causes containers to become inaccessible from external networks even though they're running.

## Solution Overview
We've created a comprehensive script that adds iptables rules for ALL containers on your homepage, and a systemd service to run it automatically on boot.

## Quick Fix (Run Now)
To fix all containers immediately:

```bash
cd ~/projects/docker
chmod +x scripts/fix-all-docker-iptables.sh
sudo ./scripts/fix-all-docker-iptables.sh
```

This will add iptables rules for:
- **Media**: Jellyfin (8096), Audiobookshelf (13378), Navidrome (4533)
- **Books**: GreatReads Prod (8007), GreatReads Dev (8008), Kavita (5000)
- **Forge Apps**: LifeForge (8004), ArtForge (8003), WordForge (8002), CodeForge (8009)
- **Photos**: Immich (2283)
- **Gaming**: Romm (8082)
- **Downloads**: qBittorrent (2285), Jackett (9117), YT-DLP Web (8998)
- **Other**: Dashboard (8001), Picard (5800), Beets (8337)

## Permanent Solution (Persistence)

### Option 1: Systemd Service (Recommended)
This runs the fix script automatically 30 seconds after Docker starts on every boot.

```bash
# Copy the service file
sudo cp ~/projects/docker/scripts/docker-iptables.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable the service
sudo systemctl enable docker-iptables.service

# Test it (optional)
sudo systemctl start docker-iptables.service
sudo systemctl status docker-iptables.service
```

### Option 2: Cron Job
Add to root's crontab:

```bash
sudo crontab -e
```

Add this line:
```
@reboot sleep 60 && /home/brandon/projects/docker/scripts/fix-all-docker-iptables.sh
```

### Option 3: iptables-persistent Package
Install and save current rules:

```bash
sudo apt-get install iptables-persistent
sudo ./scripts/fix-all-docker-iptables.sh
sudo iptables-save > /etc/iptables/rules.v4
```

**Warning**: This saves ALL iptables rules, including any custom rules you have. Be careful when updating.

## Verification

### Check if rules are applied
```bash
# Check NAT rules
sudo iptables -t nat -L DOCKER -n | grep -E "2283|8096|8082"

# Check filter rules
sudo iptables -L DOCKER -n | grep -E "2283|8096|8082"

# Check network isolation
sudo iptables -L DOCKER-ISOLATION-STAGE-1 -n
```

### Test external access
From another machine or your browser:
```bash
# Jellyfin
curl -I http://100.123.154.40:8096

# Immich
curl -I http://100.123.154.40:2283

# Romm
curl -I http://100.123.154.40:8082
```

## Container IP and Port Reference

| Service | Host Port | Container IP | Container Port | Bridge |
|---------|-----------|--------------|----------------|--------|
| Immich | 2283 | 172.31.0.5 | 2283 | br-63a5fc5a72cf |
| Jellyfin | 8096 | 192.168.16.2 | 8096 | br-bab1eaec371f |
| Romm | 8082 | 192.168.80.3 | 8080 | br-1ce630bbb57a |
| LifeForge | 8004 | 192.168.112.2 | 8004 | br-01aa55656fca |
| ArtForge | 8003 | 172.26.0.2 | 8003 | br-f6142088b2b0 |
| WordForge | 8002 | 172.25.0.2 | 8002 | br-38852d66c5eb |
| CodeForge | 8009 | 172.27.0.2 | 8000 | br-63147175c058 |
| GreatReads Prod | 8007 | 172.21.0.2 | 8006 | br-67753b61ea19 |
| GreatReads Dev | 8008 | 172.24.0.2 | 8006 | br-7f3b7e15b730 |
| Audiobookshelf | 13378 | 192.168.64.2 | 80 | br-fad0b11692e0 |
| qBittorrent | 2285 | 172.32.0.2 | 8080 | br-c1ac5e711d83 |
| Jackett | 9117 | 172.32.0.2 | 9117 | br-c1ac5e711d83 |
| YT-DLP Web | 8998 | 172.29.0.2 | 3033 | br-9deb05da66a0 |
| Kavita | 5000 | 192.168.48.2 | 5000 | br-37584833251b |
| Navidrome | 4533 | 172.28.0.2 | 4533 | br-0b8c6c77b4ec |
| Picard | 5800 | 192.168.32.2 | 5800 | br-0ecc35eb449e |
| Beets | 8337 | 192.168.96.2 | 8337 | br-291f837586fb |
| Dashboard | 8001 | 172.22.0.2 | 5000 | br-afa60917f2db |

## Troubleshooting

### Container IP changed after restart
If a container's IP changes, you'll need to update the script:
1. Find the new IP: `docker inspect <container> --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'`
2. Update the corresponding line in `scripts/fix-all-docker-iptables.sh`
3. Re-run the script

### Service not starting on boot
Check the service status:
```bash
sudo systemctl status docker-iptables.service
journalctl -u docker-iptables.service
```

### Rules disappear after Docker restart
This is expected. The systemd service only runs on boot. To fix after a Docker restart:
```bash
sudo ./scripts/fix-all-docker-iptables.sh
```

## Related Documentation
- `DOCKER_IPTABLES_FIX.md` - Original fix for Jellyfin and Immich
- `DOCKER_NETWORKING_FIX.md` - Subnet-related networking issues

## Status
- **Created**: 2026-01-01
- **Last Updated**: 2026-01-01
- **Containers Covered**: 18 services

