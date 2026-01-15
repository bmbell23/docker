# Docker iptables Fix - Jellyfin & Immich Access Issues

## Problem Summary
After a Docker daemon restart on 2026-01-01, both Jellyfin and Immich became inaccessible from external networks (192.168.0.158 and Tailscale 100.123.154.40), even though:
- Containers were running and healthy
- Localhost access worked fine
- docker-proxy processes were listening on ports
- No UFW firewall was active

## Root Cause
Docker failed to recreate necessary iptables rules after the daemon restart. Specifically:

1. **Missing NAT (DNAT) rules**: No port forwarding from host ports to container IPs
2. **Missing DOCKER chain rules**: No ACCEPT rules for container ports
3. **Missing network isolation rules**: Immich network (br-63a5fc5a72cf) was not added to DOCKER-ISOLATION-STAGE-1 chain
4. **Missing forward rules**: Immich network was not added to DOCKER-FORWARD chain

This caused:
- **Jellyfin**: External access blocked (no NAT rules)
- **Immich**: External access blocked + database connection timeout (inter-container traffic blocked)

## Solution
Run the fix script to manually add the missing iptables rules:

```bash
cd ~/projects/docker
./scripts/fix-docker-iptables.sh
```

## Manual Fix (if script doesn't work)

### Jellyfin (port 8096 -> 192.168.16.2)
```bash
# NAT rule for external access
sudo iptables -t nat -A DOCKER ! -i br-bab1eaec371f -p tcp -m tcp --dport 8096 -j DNAT --to-destination 192.168.16.2:8096

# Filter rule to allow traffic
sudo iptables -A DOCKER ! -i br-bab1eaec371f -o br-bab1eaec371f -p tcp -m tcp --dport 8096 -j ACCEPT
```

### Immich (port 2283 -> 172.31.0.5)
```bash
# NAT rule for external access
sudo iptables -t nat -A DOCKER ! -i br-63a5fc5a72cf -p tcp -m tcp --dport 2283 -j DNAT --to-destination 172.31.0.5:2283

# Filter rule to allow external traffic
sudo iptables -A DOCKER ! -i br-63a5fc5a72cf -o br-63a5fc5a72cf -p tcp -m tcp --dport 2283 -j ACCEPT

# Allow inter-container communication (critical for database access)
sudo iptables -I DOCKER 1 -i br-63a5fc5a72cf -o br-63a5fc5a72cf -j ACCEPT

# Add to isolation chain
sudo iptables -I DOCKER-ISOLATION-STAGE-1 1 -i br-63a5fc5a72cf ! -o br-63a5fc5a72cf -j DOCKER-ISOLATION-STAGE-2

# Add to forward chain
sudo iptables -I DOCKER-FORWARD 1 -i br-63a5fc5a72cf -j ACCEPT
sudo iptables -I DOCKER-FORWARD 1 -o br-63a5fc5a72cf -j ACCEPT
```

## Verification

### Check NAT rules
```bash
sudo iptables -t nat -L DOCKER -n | grep -E "8096|2283"
```
Expected output:
```
DNAT       tcp  --  0.0.0.0/0            0.0.0.0/0            tcp dpt:8096 to:192.168.16.2:8096
DNAT       tcp  --  0.0.0.0/0            0.0.0.0/0            tcp dpt:2283 to:172.31.0.5:2283
```

### Check filter rules
```bash
sudo iptables -L DOCKER -n | grep -E "8096|2283|br-63a5fc5a72cf"
```

### Test external access
```bash
# Jellyfin
curl -I http://192.168.0.158:8096

# Immich
curl -I http://192.168.0.158:2283
```

### Check Immich logs
```bash
docker logs immich_server --tail 20
```
Should show: "Immich Server is listening" and "Nest application successfully started"

## Why This Happened
Docker's iptables integration should automatically create these rules when containers start, but after a daemon restart, it failed to do so. This is likely due to:
1. Timing issues during startup
2. Conflicts with existing iptables rules
3. Docker daemon configuration issues

## Prevention
These iptables rules are **not persistent** across reboots. To make them persistent:

### Option 1: Run fix script after Docker starts
Add to a systemd service or cron job:
```bash
@reboot sleep 30 && /home/brandon/projects/docker/scripts/fix-docker-iptables.sh
```

### Option 2: Save iptables rules
```bash
# After running the fix script
sudo iptables-save > /etc/iptables/rules.v4
```

### Option 3: Restart containers (may work)
```bash
cd ~/projects/docker/jellyfin && docker compose restart
cd ~/projects/docker/immich-main && docker compose restart
```

## Related Issues
- See `DOCKER_NETWORKING_FIX.md` for subnet-related networking issues
- Immich database connection timeouts were caused by missing DOCKER-FORWARD rules

## Status
- **Fixed**: 2026-01-01 15:45 UTC
- **Jellyfin**: ✅ Accessible on port 8096
- **Immich**: ✅ Accessible on port 2283, database connection working

## Technical Details
- Jellyfin network: br-bab1eaec371f (192.168.16.0/20)
- Jellyfin container IP: 192.168.16.2
- Immich network: br-63a5fc5a72cf (172.31.0/16)
- Immich server IP: 172.31.0.5
- Immich database IP: 172.31.0.3

