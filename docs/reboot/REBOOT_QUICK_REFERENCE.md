# 🚀 Server Reboot - Quick Reference

## Before Reboot (5-10 minutes)

```bash
cd /home/brandon/projects/docker

# 1. Backup everything
./pre-reboot-backup.sh

# 2. Safely shutdown Immich (CRITICAL!)
./immich-safe-shutdown.sh

# 3. Reboot
sudo reboot
```

## After Reboot (2-3 minutes)

```bash
cd /home/brandon/projects/docker

# 1. Wait 2-3 minutes for services to start

# 2. Verify all services
./post-reboot-verify.sh

# 3. Test Immich
# Open browser: http://YOUR_SERVER_IP:2283
```

## 🆘 Emergency Recovery

### If Immich Database is Corrupted:

```bash
# Find latest backup
ls -lt /home/brandon/backups/ | head -5

# Restore from backup
cd /home/brandon/backups/pre-reboot-YYYYMMDD-HHMMSS/
gunzip immich_postgres_immich.sql.gz
docker exec -i immich_postgres psql -U postgres immich < immich_postgres_immich.sql
```

### If a Service Won't Start:

```bash
# Check logs
docker logs <container-name>

# Restart service
cd /home/brandon/projects/docker/<service-directory>
docker-compose down
docker-compose up -d
```

## 📊 Service Status

```bash
# Check all containers
docker ps -a

# Check specific service
docker logs <container-name> --tail 50

# Check Immich database
docker exec immich_postgres pg_isready -U postgres
```

## 🔧 Common Issues

| Problem | Solution |
|---------|----------|
| Immich won't start | Check logs: `docker logs immich_postgres` |
| Database corrupted | Restore from backup (see above) |
| Container not found | `cd <service-dir> && docker-compose up -d` |
| Port conflicts | Check `docker ps` for port mappings |

## 📞 Help

Full guide: `/home/brandon/projects/docker/REBOOT_GUIDE.md`

