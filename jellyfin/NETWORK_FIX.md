# Jellyfin Network Fix - January 19, 2026

## Problem
Jellyfin was not accessible via Tailscale (100.123.154.40:8096) after container restart, even though:
- Container was running and healthy
- Localhost access worked (127.0.0.1:8096)
- Local network access worked (10.0.0.160:8096)
- Port 8096 was listening

## Root Causes

### 1. Conflicting Docker Network Subnet
Jellyfin's docker-compose.yml didn't specify a network subnet, so Docker auto-assigned `192.168.16.0/20` which conflicts with common LAN networks (192.168.x.x).

**Solution:** Force Docker to use `172.x.x.x` subnet by adding explicit network configuration.

### 2. Stale iptables NAT Rules
After container restart, old iptables rules pointing to the previous network (br-bab1eaec371f / 192.168.16.2) remained, blocking traffic to the new network (br-4d578cc17712 / 172.23.0.2).

**Solution:** Remove stale rules and update the fix script with correct bridge/IP.

### 3. Missing Tailscale Routing Rules
Docker containers need special iptables rules to be accessible from Tailscale network.

**Solution:** Run tailscale-docker-routing script to add FORWARD rules.

## Fixes Applied

### 1. Updated docker-compose.yml
Added explicit network configuration to force `172.23.0.0/16` subnet:

```yaml
networks:
  default:
    driver: bridge
    ipam:
      config:
        - subnet: 172.23.0.0/16
          gateway: 172.23.0.1
```

### 2. Updated fix-all-docker-iptables.sh
Changed Jellyfin configuration from:
```bash
# OLD (wrong)
add_network_rules "br-bab1eaec371f"
add_nat_rule "br-bab1eaec371f" 8096 "192.168.16.2" 8096
```

To:
```bash
# NEW (correct)
add_network_rules "br-4d578cc17712"
add_nat_rule "br-4d578cc17712" 8096 "172.23.0.2" 8096
```

### 3. Removed Stale iptables Rules
```bash
sudo iptables -t nat -D DOCKER -p tcp ! -i br-bab1eaec371f --dport 8096 -j DNAT --to-destination 192.168.16.2:8096
```

### 4. Added Tailscale Routing
```bash
sudo /home/brandon/projects/docker/scripts/tailscale-docker-routing-new.sh
```

## Verification

```bash
# Check container is running
docker ps | grep jellyfin

# Check container IP
docker inspect jellyfin --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
# Should show: 172.23.0.2

# Check NAT rules
sudo iptables -t nat -L DOCKER -n | grep 8096
# Should show: DNAT tcp -- !br-4d578cc17712 * 0.0.0.0/0 0.0.0.0/0 tcp dpt:8096 to:172.23.0.2:8096

# Test access
curl -I http://localhost:8096          # Local
curl -I http://10.0.0.160:8096         # LAN
curl -I http://100.123.154.40:8096     # Tailscale
```

## Persistence on Reboot

The systemd service `docker-iptables.service` runs automatically 30 seconds after Docker starts on every boot. It now has the correct Jellyfin configuration.

To verify after reboot:
```bash
sudo systemctl status docker-iptables.service
journalctl -u docker-iptables.service
```

## How to Restart Jellyfin (AppArmor Workaround)

**NEVER USE:** `docker restart jellyfin` (fails with permission denied)

**ALWAYS USE:**
```bash
PID=$(docker inspect jellyfin --format '{{.State.Pid}}')
sudo kill $PID
cd /home/brandon/projects/docker/jellyfin
docker compose up -d
```

## Network Information

- **LAN Network:** 10.0.0.0/24 (gateway: 10.0.0.1)
- **Server LAN IP:** 10.0.0.160
- **Server Tailscale IP:** 100.123.154.40
- **Jellyfin Docker Network:** 172.23.0.0/16 (br-4d578cc17712)
- **Jellyfin Container IP:** 172.23.0.2
- **Jellyfin Ports:** 8096 (HTTP), 8920 (HTTPS), 7359/udp (discovery), 1900/udp (DLNA)

## Related Documentation

- `/home/brandon/projects/docker/docs/docker/DOCKER_IPTABLES_FIX.md`
- `/home/brandon/projects/docker/docs/docker/DOCKER_NETWORKING_FIX.md`
- `/home/brandon/projects/docker/docs/docker/DOCKER_IPTABLES_PERSISTENCE.md`
- `/home/brandon/projects/docker/docs/ai-guidelines/AGENTS.md` (AppArmor workaround)

## Status
✅ **FIXED** - January 19, 2026
- Accessible on localhost: http://127.0.0.1:8096
- Accessible on LAN: http://10.0.0.160:8096
- Accessible on Tailscale: http://100.123.154.40:8096
- Persists across reboots via systemd service

