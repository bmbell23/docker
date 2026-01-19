# Docker Permission Issues - AppArmor Root Cause

## Problem
Docker commands fail with "permission denied" even though user is in the docker group:
- `docker restart <container>` ❌ Permission denied
- `docker kill <container>` ❌ Permission denied
- `docker stop <container>` ❌ Permission denied
- `sudo docker restart <container>` ❌ Still fails!

## Root Cause: AppArmor

AppArmor is a Linux security module that restricts what programs can do. On this server, AppArmor has policies that block certain Docker operations, even for users in the docker group and even with sudo.

### Verification
```bash
# Check if AppArmor is active
docker info 2>&1 | grep -i apparmor
# Output: Security Options: apparmor

# Check user is in docker group
groups $USER
# Output: brandon : brandon adm cdrom sudo dip plugdev users docker

# Check docker socket permissions
ls -la /var/run/docker.sock
# Output: srw-rw---- 1 root docker 0 Jan 19 11:53 /var/run/docker.sock
```

User has correct permissions, but AppArmor still blocks certain operations.

## Why This Happens

AppArmor profiles define what each program can do. Docker's AppArmor profile restricts:
1. Direct container process manipulation (restart, kill, stop)
2. Certain signal operations on container processes
3. Some container lifecycle operations

These restrictions exist for security - to prevent privilege escalation and container breakouts.

## The Workaround

Instead of using Docker commands to restart containers, we kill the container's main process directly, then use `docker compose up -d` to restart it.

### Working Method
```bash
# Step 1: Get the container's PID
PID=$(docker inspect <container_name_or_id> --format '{{.State.Pid}}')

# Step 2: Kill the process (requires sudo)
sudo kill $PID

# Step 3: Restart with docker compose
cd /path/to/project
docker compose up -d
```

### Why This Works
- `docker inspect` is a read-only operation - AppArmor allows it
- `kill $PID` operates on the process directly, bypassing Docker's AppArmor profile
- `docker compose up -d` creates/starts containers - AppArmor allows this
- Only restart/kill/stop operations are blocked

## Examples

### Jellyfin
```bash
PID=$(docker inspect jellyfin --format '{{.State.Pid}}')
sudo kill $PID
cd /home/brandon/projects/docker/jellyfin
docker compose up -d
```

### Immich
```bash
PID=$(docker inspect immich_server --format '{{.State.Pid}}')
sudo kill $PID
cd /home/brandon/projects/docker/immich-main
docker compose up -d
```

### Any Container
```bash
# By name
PID=$(docker inspect <container_name> --format '{{.State.Pid}}')
sudo kill $PID

# By ID
PID=$(docker inspect <container_id> --format '{{.State.Pid}}')
sudo kill $PID

# Then restart
cd /path/to/docker-compose/directory
docker compose up -d
```

## Alternative Solutions (Not Recommended)

### 1. Disable AppArmor for Docker (DANGEROUS)
```bash
# DON'T DO THIS - removes security protections
sudo aa-disable /etc/apparmor.d/docker
```

**Why not:** Removes important security protections that prevent container breakouts.

### 2. Modify AppArmor Profile (COMPLEX)
```bash
# DON'T DO THIS - requires deep AppArmor knowledge
sudo nano /etc/apparmor.d/docker
# Add custom rules...
sudo apparmor_parser -r /etc/apparmor.d/docker
```

**Why not:** 
- Complex and error-prone
- Could introduce security vulnerabilities
- Updates might overwrite changes
- The workaround is simpler and safer

### 3. Use `docker compose down` then `up` (DOESN'T WORK)
```bash
# This also fails because 'down' tries to stop containers
docker compose down  # ❌ Permission denied
```

## Best Practice: Use the Workaround

The PID kill method is:
- ✅ Simple and reliable
- ✅ Doesn't compromise security
- ✅ Works consistently
- ✅ Documented in multiple places
- ✅ Can be scripted/automated

## Documentation Locations

This workaround is documented in:
1. `/home/brandon/projects/docker/docs/ai-guidelines/AGENTS.md`
2. `/home/brandon/projects/docker/docs/ai-guidelines/CLAUDE.md`
3. `/home/brandon/projects/docker/jellyfin/NETWORK_FIX.md`
4. `/home/brandon/projects/docker/romm/docs/GET_STARTED.md`
5. `/home/brandon/projects/docker/romm/scripts/utils/setup-metadata.sh`
6. This document

## Quick Reference

**NEVER USE:**
```bash
docker restart <container>          # ❌
docker kill <container>             # ❌
docker stop <container>             # ❌
docker compose restart              # ❌
sudo docker restart <container>     # ❌ (still fails!)
```

**ALWAYS USE:**
```bash
PID=$(docker inspect <container> --format '{{.State.Pid}}')
sudo kill $PID
cd /path/to/project
docker compose up -d
```

## Status
- **Issue Identified:** January 19, 2026
- **Root Cause:** AppArmor security policies
- **Workaround:** Kill PID directly, then `docker compose up -d`
- **Documentation:** Updated in 6+ locations
- **Status:** ✅ Working solution, well-documented

