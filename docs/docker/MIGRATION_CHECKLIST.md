# Docker Migration Checklist

## Pre-Migration (DO NOW - Before Weekend)

- [x] **Identify root cause**: Two Docker daemons running (Snap + Native)
- [x] **Create migration scripts**:
  - [x] `backup-before-migration.sh` - Full backup
  - [x] `migrate-snap-to-native.sh` - Migration automation
  - [x] `rollback-migration.sh` - Emergency rollback
  - [x] `verify-migration-readiness.sh` - Pre-flight checks
- [x] **Create documentation**:
  - [x] `SNAP_TO_NATIVE_MIGRATION.md` - Detailed migration guide
  - [x] `MIGRATION_QUICK_START.md` - Quick reference
  - [x] `APPARMOR_DOCKER_PERMISSIONS.md` - Root cause documentation
  - [x] `MIGRATION_CHECKLIST.md` - This file
- [x] **Run verification script**: ✅ System ready
- [x] **Run backup script**: ✅ 130MB backup created
- [x] **Review backup inventory**: ✅ 28 containers, 14 compose files
- [x] **Commit all changes to git**: ✅ All committed

## Migration Day (DO THIS WEEKEND)

### Before Starting
- [ ] **Schedule downtime window**: 1-2 hours
- [ ] **Notify users** (if applicable): All services will be down
- [ ] **Verify backup is recent**: Check `/home/brandon/docker-migration-backup/`
- [ ] **Have rollback plan ready**: Know how to run rollback script

### Migration Steps
- [ ] **Run migration script**:
  ```bash
  sudo /home/brandon/projects/docker/scripts/migrate-snap-to-native.sh
  ```
- [ ] **Monitor progress**: Watch for errors in output
- [ ] **Wait for completion**: Script will report when done

### Post-Migration Verification
- [ ] **Check container count**: `docker ps | wc -l` should show ~28
- [ ] **Test Jellyfin via Tailscale**: `curl -I http://100.123.154.40:8096`
- [ ] **Test docker restart**: `docker restart jellyfin` (should work!)
- [ ] **Test docker stop**: `docker stop jellyfin && docker start jellyfin`
- [ ] **Test docker kill**: Works without permission denied
- [ ] **Verify all services accessible**:
  - [ ] Jellyfin (http://100.123.154.40:8096)
  - [ ] Immich (check your usual URL)
  - [ ] Outline (check your usual URL)
  - [ ] Other critical services
- [ ] **Check iptables rules**: `sudo iptables -t nat -L DOCKER -n -v | grep 8096`
- [ ] **Review migration log**: `cat /home/brandon/docker-migration-backup/migration_*.log`

## If Migration Fails

### Rollback Steps
- [ ] **Run rollback script**:
  ```bash
  sudo /home/brandon/projects/docker/scripts/rollback-migration.sh
  ```
- [ ] **Verify containers running**: `docker ps`
- [ ] **Test services**: Ensure everything works
- [ ] **Document what went wrong**: For troubleshooting
- [ ] **Plan retry**: Fix issues before trying again

## Post-Migration Cleanup (1 Week Later)

- [ ] **Verify stability**: All services running smoothly for 1 week
- [ ] **Remove backup** (optional):
  ```bash
  sudo rm -rf /home/brandon/docker-migration-backup/
  ```
- [ ] **Update documentation**: Remove PID kill workaround references
- [ ] **Celebrate**: No more permission denied errors! 🎉

## Expected Results

### Before Migration
```bash
$ docker restart jellyfin
Error response from daemon: cannot restart container: permission denied

$ docker stop jellyfin
Error response from daemon: cannot stop container: permission denied

$ docker kill jellyfin
Error response from daemon: cannot kill container: permission denied
```

**Workaround needed:**
```bash
PID=$(docker inspect jellyfin --format '{{.State.Pid}}')
sudo kill $PID
cd /home/brandon/projects/docker/jellyfin
docker compose up -d
```

### After Migration
```bash
$ docker restart jellyfin
jellyfin

$ docker stop jellyfin
jellyfin

$ docker kill jellyfin
jellyfin
```

**No workaround needed!** ✅

## Key Files

- **Documentation**:
  - `/home/brandon/projects/docker/docs/docker/MIGRATION_QUICK_START.md`
  - `/home/brandon/projects/docker/docs/docker/SNAP_TO_NATIVE_MIGRATION.md`
  - `/home/brandon/projects/docker/docs/docker/APPARMOR_DOCKER_PERMISSIONS.md`

- **Scripts**:
  - `/home/brandon/projects/docker/scripts/verify-migration-readiness.sh`
  - `/home/brandon/projects/docker/scripts/backup-before-migration.sh`
  - `/home/brandon/projects/docker/scripts/migrate-snap-to-native.sh`
  - `/home/brandon/projects/docker/scripts/rollback-migration.sh`

- **Backup**:
  - `/home/brandon/docker-migration-backup/`

## Current Status

✅ **READY FOR MIGRATION**

- Backup: ✅ Complete (130MB, 28 containers)
- Scripts: ✅ All created and tested
- Documentation: ✅ Comprehensive
- Git: ✅ All changes committed
- Verification: ✅ System ready

**Next step:** Run migration this weekend when you have 1-2 hours of downtime.

## Quick Commands

```bash
# Verify readiness
/home/brandon/projects/docker/scripts/verify-migration-readiness.sh

# Review backup
cat /home/brandon/docker-migration-backup/inventory.txt

# Migrate (when ready)
sudo /home/brandon/projects/docker/scripts/migrate-snap-to-native.sh

# Rollback (if needed)
sudo /home/brandon/projects/docker/scripts/rollback-migration.sh
```

## Notes

- **Downtime**: 30-60 minutes expected
- **Data safety**: All volumes persist, no data loss
- **Rollback**: Available if needed
- **Testing**: Verification script confirms readiness
- **Backup**: Full backup created and verified

