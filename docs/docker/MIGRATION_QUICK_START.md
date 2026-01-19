# Docker Migration Quick Start Guide

## TL;DR - What's the Problem?

You have **TWO Docker daemons running at the same time**:
- Snap Docker (running all your containers)
- Native Docker (installed but mostly idle)

This causes `docker restart/kill/stop` to fail with "permission denied" due to conflicts and AppArmor restrictions.

## The Fix

Migrate from Snap Docker to native Docker. This will:
- ✅ Fix permission denied errors permanently
- ✅ Remove need for PID kill workaround
- ✅ Improve performance
- ✅ Give you standard Docker behavior

## Quick Commands

### 1. Verify System is Ready (DO THIS NOW)
```bash
/home/brandon/projects/docker/scripts/verify-migration-readiness.sh
```

### 2. Create Backup (DO THIS NOW)
```bash
sudo /home/brandon/projects/docker/scripts/backup-before-migration.sh
```

### 3. Review Backup
```bash
cat /home/brandon/docker-migration-backup/inventory.txt
```

### 4. Migrate (DO THIS WEEKEND)
```bash
sudo /home/brandon/projects/docker/scripts/migrate-snap-to-native.sh
```

### 5. If Something Goes Wrong (Rollback)
```bash
sudo /home/brandon/projects/docker/scripts/rollback-migration.sh
```

## What Each Script Does

### verify-migration-readiness.sh
- ✅ Checks both Docker installations exist
- ✅ Verifies backup is ready
- ✅ Confirms docker-compose files are present
- ✅ Checks disk space
- ✅ Validates git status
- ✅ Ensures migration scripts are executable

### backup-before-migration.sh
- 📦 Creates full backup of all configs
- 📦 Saves list of all containers, volumes, networks
- 📦 Documents current state
- 📦 Creates checksums for verification
- 📦 Saves to: `/home/brandon/docker-migration-backup/`

### migrate-snap-to-native.sh
- 🔄 Stops all containers gracefully
- 🔄 Stops Snap Docker daemon
- 🔄 Removes Snap Docker
- 🔄 Starts native Docker daemon
- 🔄 Recreates all containers from docker-compose files
- 🔄 Applies iptables rules for Tailscale
- 🔄 Verifies everything works

### rollback-migration.sh
- ⏮️ Stops native Docker
- ⏮️ Reinstalls Snap Docker
- ⏮️ Restores all containers
- ⏮️ Gets you back to working state

## Timeline

### Today (Preparation)
1. Run verification script (2 minutes)
2. Run backup script (5-10 minutes)
3. Review backup inventory (2 minutes)
4. Commit all changes to git (1 minute)

**Total time: ~15 minutes, NO downtime**

### This Weekend (Migration)
1. Run migration script (30-60 minutes)
2. Verify all containers running (5 minutes)
3. Test Jellyfin via Tailscale (1 minute)
4. Test docker restart command (1 minute)

**Total time: ~45-70 minutes, ALL containers down during migration**

## Expected Results

### Before Migration
```bash
$ docker restart jellyfin
Error response from daemon: cannot restart container: permission denied
```

### After Migration
```bash
$ docker restart jellyfin
jellyfin
```

**No more permission denied! 🎉**

## Safety

- ✅ **All data is safe** - Volumes persist across Docker installations
- ✅ **Full backup created** - Can restore if needed
- ✅ **Rollback script ready** - Can undo migration
- ✅ **Git tracked** - All configs version controlled
- ✅ **Tested approach** - Standard migration procedure

## What Gets Migrated

✅ All containers (28+ containers)  
✅ All volumes (data persists)  
✅ All networks (recreated from docker-compose)  
✅ All docker-compose configurations  
✅ All iptables rules for Tailscale  

## What Changes

❌ Snap Docker removed  
✅ Native Docker becomes primary  
✅ Docker commands work normally  
✅ No more PID kill workaround needed  

## Questions?

- **Will I lose data?** No, volumes persist on disk
- **Can I rollback?** Yes, rollback script is ready
- **How long is downtime?** 30-60 minutes
- **What if it fails?** Run rollback script
- **When should I do this?** Weekend when you have time

## Current Status

Run this to check current status:
```bash
ps aux | grep dockerd | grep -v grep
```

You should see TWO dockerd processes:
- `/snap/docker/.../dockerd` (Snap Docker - running your containers)
- `/usr/bin/dockerd` (Native Docker - mostly idle)

After migration, you'll only see:
- `/usr/bin/dockerd` (Native Docker - running everything)

## Ready to Start?

```bash
# Step 1: Verify readiness
/home/brandon/projects/docker/scripts/verify-migration-readiness.sh

# Step 2: Create backup
sudo /home/brandon/projects/docker/scripts/backup-before-migration.sh

# Step 3: Review backup
cat /home/brandon/docker-migration-backup/inventory.txt

# Step 4: Wait for weekend, then migrate
sudo /home/brandon/projects/docker/scripts/migrate-snap-to-native.sh
```

Good luck! 🚀

