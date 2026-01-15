# Immich Troubleshooting Guide

## Issue: Immich Server Container Down - Port Conflict

### Problem Description

The Immich server container fails to start or is missing from the running containers list. When attempting to start the container, you may see an error like:

```
Error response from daemon: driver failed programming external connectivity on endpoint immich_server: 
Error starting userland proxy: listen tcp4 0.0.0.0:2283: bind: address already in use
```

Supporting containers (postgres, redis, machine-learning) may still be running, but the main `immich_server` container is down.

### Root Cause

Port 2283 is being held by stale `docker-proxy` processes from a previous failed container start attempt. This typically happens after:
- System crash or unexpected shutdown
- Docker daemon restart
- Failed container start that wasn't properly cleaned up
- Manual container stop without proper cleanup

### Symptoms

1. **Missing Container**: `immich_server` doesn't appear in `docker ps`
2. **Port Conflict Error**: Attempting to start shows "address already in use" on port 2283
3. **Partial Stack**: Other Immich containers (postgres, redis, machine-learning) are running
4. **Inaccessible Service**: Cannot access Immich at http://localhost:2283

### Solution

#### Quick Fix (Recommended)

```bash
# 1. Check what's using port 2283
sudo lsof -i :2283

# Output will show something like:
# COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
# docker-pr 1127081 root    4u  IPv4 123456      0t0  TCP *:2283 (LISTEN)
# docker-pr 1127095 root    4u  IPv6 123457      0t0  TCP *:2283 (LISTEN)

# 2. Kill the processes holding the port (replace PIDs with actual numbers from step 1)
sudo kill -9 <PID1> <PID2>

# Example:
# sudo kill -9 1127081 1127095

# 3. Navigate to Immich directory and start services
cd ~/projects/docker/immich-main
docker compose up -d

# 4. Verify all containers are running
docker ps --filter "name=immich"

# Expected output should show:
# - immich_server (Running)
# - immich_postgres (Running, healthy)
# - immich_redis (Running, healthy)
# - immich_machine_learning (Running, healthy)
```

#### Alternative: Full Docker Restart (Nuclear Option)

If killing the processes doesn't work, restart Docker entirely:

```bash
# 1. Restart Docker daemon
sudo systemctl restart docker

# 2. Wait a few seconds for Docker to fully restart
sleep 5

# 3. Start Immich
cd ~/projects/docker/immich-main
docker compose up -d

# 4. Verify containers are running
docker ps --filter "name=immich"
```

### Verification

After applying the fix, verify that Immich is working:

```bash
# Check container status
docker ps --filter "name=immich"

# All containers should show "Up" status
# immich_server should show "health: starting" initially, then "healthy" after 1-2 minutes

# Check logs for any errors
docker compose logs immich-server --tail=50

# Access Immich web interface
# Open browser to: http://100.123.154.40:2283 (or your server IP)
```

### Prevention

To prevent this issue in the future:

1. **Graceful Shutdown**: Always use `docker compose down` instead of killing containers
2. **Clean Restarts**: If you need to restart, use:
   ```bash
   docker compose down
   docker compose up -d
   ```
3. **Monitor Health**: Regularly check container health:
   ```bash
   docker ps --filter "name=immich"
   ```

### Additional Diagnostics

If the issue persists after trying the above solutions:

```bash
# Check if port is still in use
sudo netstat -tulpn | grep 2283

# Check Docker network status
docker network ls
docker network inspect immich-main_default

# Check for zombie containers
docker ps -a | grep immich

# Remove any stopped Immich containers
docker compose down
docker compose up -d

# Check Docker daemon logs
sudo journalctl -u docker -n 100 --no-pager

# Verify docker-compose.yml is correct
cd ~/projects/docker/immich-main
docker compose config
```

### Related Issues

- **Database Connection Errors**: If postgres is unhealthy, check logs with `docker compose logs immich-postgres`
- **Redis Connection Errors**: Check redis with `docker compose logs immich-redis`
- **Machine Learning Errors**: Check ML service with `docker compose logs immich-machine-learning`

### When to Seek Further Help

If none of the above solutions work:
1. Check Immich GitHub issues: https://github.com/immich-app/immich/issues
2. Review Immich Discord: https://discord.gg/immich
3. Collect diagnostic information:
   ```bash
   docker compose logs > immich_logs.txt
   docker ps -a > docker_containers.txt
   sudo lsof -i :2283 > port_usage.txt
   ```

### Summary

**Problem**: Immich server container down due to port 2283 conflict  
**Quick Fix**: `sudo lsof -i :2283` → `sudo kill -9 <PIDs>` → `docker compose up -d`  
**Prevention**: Always use `docker compose down` before restarting  
**Verification**: Check with `docker ps --filter "name=immich"` and access http://your-ip:2283

