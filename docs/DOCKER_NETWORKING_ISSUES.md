# Docker Networking and iptables Issues

## Overview

This document describes common Docker networking issues related to iptables rules and port forwarding, particularly after Docker daemon restarts or system reboots.

## Common Issues

### 1. Inter-Container Communication Failures

**Symptoms:**
- Containers show as "healthy" in `docker ps` but cannot communicate with each other
- Connection timeouts when containers try to reach other containers on the same network
- Logs show errors like:
  - `connect ETIMEDOUT`
  - `Redis error: connect ETIMEDOUT`
  - `Failed to connect to database`
- Services that worked before a Docker restart suddenly fail

**Root Cause:**
After Docker daemon restarts, Docker sometimes fails to properly recreate iptables rules for certain bridge networks. Specifically, the following iptables chains may be missing rules:
- `DOCKER-ISOLATION-STAGE-1` - Controls traffic between different Docker networks
- `DOCKER-FORWARD` - Controls forwarding of traffic to/from Docker networks
- `DOCKER` - Controls traffic within Docker networks

**Diagnosis:**
```bash
# Get the bridge name for your network
docker network ls
# Look for your network, e.g., "outline_outline_network" with ID "c3f69129e352"
# Bridge name will be "br-c3f69129e352" (first 12 chars of ID)

# Check if the bridge has rules in DOCKER-ISOLATION-STAGE-1
sudo iptables -L DOCKER-ISOLATION-STAGE-1 -n -v | grep "br-c3f69129e352"
# Should show: DOCKER-ISOLATION-STAGE-2  all  --  br-c3f69129e352 !br-c3f69129e352  0.0.0.0/0  0.0.0.0/0

# Check if the bridge has rules in DOCKER-FORWARD
sudo iptables -L DOCKER-FORWARD -n -v | grep "br-c3f69129e352"
# Should show multiple ACCEPT rules for the bridge

# If these commands return nothing, the rules are missing!
```

**Solution:**
Run the fix script:
```bash
sudo ./scripts/fix-docker-iptables.sh
```

**Permanent Solution:**
Install the systemd service to run the fix script automatically on boot:
```bash
sudo cp scripts/fix-docker-iptables.service /etc/systemd/system/
sudo systemctl enable fix-docker-iptables.service
sudo systemctl start fix-docker-iptables.service
```

### 2. Port Forwarding Issues (Stale NAT Rules)

**Symptoms:**
- Cannot access a container from outside (e.g., via Tailscale IP)
- `curl http://100.123.154.40:PORT/` fails with "Could not connect to server"
- Container is accessible via `localhost:PORT` but not via external IP

**Root Cause:**
After Docker daemon restarts, old iptables NAT rules may persist that point to old container IP addresses. When Docker recreates containers, they get new IP addresses, but the old NAT rules are still matched first.

**Diagnosis:**
```bash
# Check NAT rules for your port
sudo iptables -t nat -L DOCKER -n -v --line-numbers | grep "PORT"

# Check if there are duplicate rules or rules pointing to wrong IPs
# Example: If you see two rules for port 2283, one pointing to 172.31.0.5 and one to 172.31.0.4,
# and your container is actually at 172.31.0.4, then the first rule (172.31.0.5) is stale.

# Get the actual container IP
docker inspect CONTAINER_NAME | grep IPAddress
```

**Solution:**
Delete the stale NAT rule:
```bash
# Delete by line number (from the diagnosis step above)
sudo iptables -t nat -D DOCKER LINE_NUMBER

# Example:
sudo iptables -t nat -D DOCKER 6
```

## Prevention

### Automatic Fix on Boot

The systemd service will automatically run the fix script after Docker starts:

```bash
# Install the service
sudo cp scripts/fix-docker-iptables.service /etc/systemd/system/
sudo systemctl enable fix-docker-iptables.service

# Check status
sudo systemctl status fix-docker-iptables.service
```

### Manual Fix After Docker Restart

If you restart Docker manually, run the fix script:
```bash
sudo systemctl restart docker
sleep 10  # Wait for Docker to fully start
sudo ./scripts/fix-docker-iptables.sh
```

## Affected Services

The following services are known to be affected by these issues:

1. **Outline** (`outline_outline_network`)
   - Symptoms: Cannot connect to Redis or Postgres
   - Port: 8000

2. **Immich** (`immich-main_default`)
   - Symptoms: Cannot connect to Redis or Postgres
   - Port: 2283

3. **Jellyfin** (`jellyfin_default`)
   - Port: 8096

## Troubleshooting Commands

```bash
# List all Docker networks and their bridge interfaces
docker network ls
docker network inspect NETWORK_NAME | grep -E "\"Id\"|\"com.docker.network.bridge.name\""

# List all iptables rules for Docker
sudo iptables -L -n -v | grep -E "DOCKER|Chain"
sudo iptables -t nat -L -n -v | grep -E "DOCKER|Chain"

# Check specific chains
sudo iptables -L DOCKER-ISOLATION-STAGE-1 -n -v
sudo iptables -L DOCKER-FORWARD -n -v
sudo iptables -L DOCKER -n -v
sudo iptables -t nat -L DOCKER -n -v

# Check container logs for connection errors
docker logs CONTAINER_NAME --tail 50 | grep -i "error\|timeout"

# Test connectivity from inside a container
docker exec CONTAINER_NAME getent hosts OTHER_CONTAINER_NAME
```

## References

- [Docker iptables documentation](https://docs.docker.com/network/iptables/)
- [Docker networking overview](https://docs.docker.com/network/)

