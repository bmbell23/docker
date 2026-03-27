---
type: "always_apply"
---

# Docker Container Management Rules

## Critical: Container Restart Procedure

**NEVER use `docker compose down` or `docker compose restart` directly** - these commands often fail with permission errors even with sudo.

### Proper Container Restart Process

When restarting containers (especially VPN-dependent ones like mullvad-vpn, qbittorrent, jackett, flaresolverr):

1. **Kill the container processes first:**
   ```bash
   sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | xargs -I {} sh -c 'sudo docker inspect {} 2>/dev/null | grep "\"Pid\"" | grep -o "[0-9]*" | xargs -I PID sudo kill -9 PID 2>/dev/null'
   ```

2. **Remove the stopped containers:**
   ```bash
   sudo docker ps -a | grep -E "qbittorrent|jackett|flaresolverr|mullvad" | awk '{print $1}' | xargs sudo docker rm -f
   ```

3. **Restart in dependency order:**
   ```bash
   cd /home/brandon/projects/docker/torrents && sudo docker compose up -d
   sleep 5
   cd /home/brandon/projects/docker/jackett && sudo docker compose up -d
   ```

**Why this is necessary:** Docker sometimes has permission issues killing containers even with sudo. Killing the process directly with `kill -9` on the PID bypasses this issue.

## VPN Network Architecture

### Current Setup

- **Mullvad VPN Container** (`mullvad-vpn`): Main VPN gateway using WireGuard
- **Containers routing through VPN:**
  - `qbittorrent` - Uses `network_mode: "service:vpn"`
  - `jackett` - Uses `network_mode: "container:mullvad-vpn"`
  - `flaresolverr` - Uses `network_mode: "container:mullvad-vpn"`
- **Containers NOT using VPN:**
  - `deemix` - Uses normal connection (Deezer blocks VPN IPs)

### Port Exposure

When containers use `network_mode: "container:X"` or `network_mode: "service:X"`:
- They share the network namespace with container X
- Ports must be exposed on the VPN container, NOT the dependent container
- Example: Jackett's port 9117 is exposed on `mullvad-vpn`, not on `jackett`

### DNS Configuration - CRITICAL

**Mullvad VPN blocks external DNS queries (8.8.8.8, 1.1.1.1, etc.)**

You MUST use Mullvad's DNS server: `10.64.0.1`

#### Two places DNS must be configured:

1. **WireGuard config file** (`torrents/se-got-wg-008.conf`):
   ```
   DNS = 10.64.0.1
   ```
   **DO NOT use:** `DNS = 8.8.8.8,8.8.4.4,1.1.1.1` - Mullvad will block these!

2. **Docker Compose** (`torrents/docker-compose.yml`):
   ```yaml
   dns:
     - 10.64.0.1
   ```

**Why both?** The WireGuard container uses `resolvconf` which reads the DNS line from the WireGuard config and writes it to `/etc/resolv.conf`. The docker-compose DNS setting is a fallback but the WireGuard config takes precedence.

#### Verifying DNS is working:

```bash
# Check DNS config in container
sudo docker exec mullvad-vpn cat /etc/resolv.conf
# Should show: nameserver 10.64.0.1

# Test DNS resolution
sudo docker exec mullvad-vpn nslookup google.com
# Should resolve successfully

# Test from dependent container
sudo docker exec jackett curl -I https://google.com
# Should connect successfully
```

## Removing Containers from VPN

If you need to remove a container from VPN routing (like we did with Deemix):

1. **Remove `network_mode` from the container's docker-compose.yml**
2. **Add direct port exposure to the container**
3. **Remove the port from the VPN container** (if it was exposed there)
4. **Restart both containers** using the proper restart procedure above

Example - Deemix removal from VPN:
- Removed: `network_mode: "container:mullvad-vpn"` from deemix/docker-compose.yml
- Added: `ports: - "6595:6595"` to deemix/docker-compose.yml
- Removed: `- "6595:6595"` from mullvad-vpn ports in torrents/docker-compose.yml

## Common Issues and Solutions

### Issue: DNS resolution fails (SERVFAIL)
**Symptoms:** `nslookup google.com` returns SERVFAIL, containers can't resolve domain names
**Cause:** Using external DNS servers (8.8.8.8, 1.1.1.1) which Mullvad blocks
**Solution:** Change DNS to `10.64.0.1` in both WireGuard config and docker-compose, then restart containers

### Issue: Permission denied when stopping containers
**Symptoms:** `docker compose down` fails with "permission denied" even with sudo
**Solution:** Use the proper restart procedure above (kill PIDs, remove containers, restart)

### Issue: Containers can ping IPs but can't resolve domains
**Symptoms:** `ping 8.8.8.8` works but `curl https://google.com` fails
**Cause:** DNS resolution is broken (see DNS resolution issue above)
**Solution:** Fix DNS configuration to use Mullvad DNS

### Issue: Container using `network_mode: "container:X"` can't access network
**Symptoms:** Container shares network with X but has different DNS or can't connect
**Cause:** DNS configuration not properly set on the parent container
**Solution:** Ensure parent container (X) has correct DNS configuration, restart both containers

## Network Mode Options

- `network_mode: "service:vpn"` - Share network with a service in the SAME docker-compose file
- `network_mode: "container:mullvad-vpn"` - Share network with a container in a DIFFERENT docker-compose file
- No network_mode specified - Container uses default bridge network (normal internet connection)

## Testing VPN Connection

```bash
# Check VPN is connected
sudo docker exec mullvad-vpn wg show

# Check external IP (should be VPN IP)
sudo docker exec mullvad-vpn curl https://ifconfig.me

# Check external IP from dependent container
sudo docker exec jackett curl https://ifconfig.me
# Should match the VPN IP

# Check Deemix is NOT using VPN
sudo docker exec deemix curl https://ifconfig.me
# Should show your real IP, not VPN IP
```

## Container Dependencies

When restarting, always restart in this order:
1. `mullvad-vpn` (VPN gateway)
2. `qbittorrent` (depends on vpn service)
3. `jackett` and `flaresolverr` (depend on mullvad-vpn container)
4. `deemix` (independent, can restart anytime)

Wait 5 seconds between VPN startup and dependent containers to ensure VPN is fully connected.
