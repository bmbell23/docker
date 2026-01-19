# Server Reboot Guide

## ⚠️ CRITICAL: Follow This Guide to Prevent Data Loss

This guide ensures all Docker services, especially **Immich**, come back up safely after a reboot without losing data.

## 📋 Pre-Reboot Checklist

### 1. Create Backups (REQUIRED)
```bash
cd /home/brandon/projects/docker
chmod +x pre-reboot-backup.sh
./pre-reboot-backup.sh
```

This will backup:
- ✅ Immich PostgreSQL database (CRITICAL)
- ✅ Outline PostgreSQL database
- ✅ Romm MariaDB database
- ✅ All service configurations
- ✅ Container states

**Expected time:** 5-10 minutes  
**Backup location:** `/home/brandon/backups/pre-reboot-YYYYMMDD-HHMMSS/`

### 2. Safely Shutdown Immich (CRITICAL)
```bash
cd /home/brandon/projects/docker
chmod +x immich-safe-shutdown.sh
./immich-safe-shutdown.sh
```

This prevents database corruption by:
- Creating an additional Immich backup
- Stopping services in the correct order
- Allowing PostgreSQL to flush buffers properly

**Why this matters:** In the past, improper shutdowns have caused Immich database corruption requiring complete reinstallation.

### 3. Verify Backups
```bash
# Check backup was created
ls -lh /home/brandon/backups/ | tail -5

# Verify Immich backup exists and has data
ls -lh /home/brandon/backups/pre-reboot-*/immich_postgres_immich.sql.gz
```

The backup file should be at least a few MB in size.

### 4. Optional: Stop Other Critical Services
If you want to be extra safe, you can stop other database services:

```bash
# Outline
cd /home/brandon/projects/docker/outline
docker-compose stop

# Romm
cd /home/brandon/projects/docker/romm
docker-compose stop romm-db
```

## 🔄 Reboot the Server

Once backups are complete and Immich is safely shut down:

```bash
sudo reboot
```

## ✅ Post-Reboot Verification

### 1. Wait for System to Boot
Wait 2-3 minutes after reboot for all services to start.

### 2. Run Verification Script
```bash
cd /home/brandon/projects/docker
chmod +x post-reboot-verify.sh
./post-reboot-verify.sh
```

This will check:
- All containers are running
- Health checks are passing
- Databases are accessible

### 3. Check Immich Specifically
```bash
# Check Immich containers
docker ps | grep immich

# Check Immich database
docker exec immich_postgres pg_isready -U postgres

# Check Immich logs
docker logs immich_server --tail 50
```

### 4. Test Immich Web Interface
Open in browser: `http://YOUR_SERVER_IP:2283`

- ✅ Can you log in?
- ✅ Can you see your photos?
- ✅ Can you upload a test photo?

## 🚨 Troubleshooting

### Immich Won't Start

**Check logs:**
```bash
docker logs immich_server
docker logs immich_postgres
```

**Common issues:**

1. **Database corruption:**
```bash
# Restore from backup
cd /home/brandon/backups/pre-reboot-YYYYMMDD-HHMMSS/
gunzip immich_postgres_immich.sql.gz
docker exec -i immich_postgres psql -U postgres immich < immich_postgres_immich.sql
```

2. **Container won't start:**
```bash
cd /home/brandon/projects/docker/immich-main
docker-compose down
docker-compose up -d
```

### Other Services Won't Start

**Check which services failed:**
```bash
docker ps -a | grep -v "Up"
```

**Restart a specific service:**
```bash
cd /home/brandon/projects/docker/<service-directory>
docker-compose up -d
```

**Check logs:**
```bash
docker logs <container-name>
```

## 📊 Service Locations

All services have `restart: unless-stopped` or `restart: always` configured, so they should automatically start after reboot.

### Critical Data Locations

| Service | Database Location | Config Location |
|---------|------------------|-----------------|
| Immich | `/home/brandon/immich/postgres` | Same |
| Jellyfin | N/A | `/home/brandon/jellyfin/config` |
| Romm | Docker volume `romm_romm-db-data` | `/home/brandon/romm` |
| Outline | `/home/brandon/projects/docker/outline/data/postgres` | Same |
| Audiobookshelf | N/A | `/home/brandon/audiobookshelf/data` |
| Kavita | N/A | `/home/brandon/kavita/data` |
| Navidrome | N/A | `/home/brandon/navidrome/data` |

## 🔧 Manual Service Restart

If a service doesn't come back up automatically:

```bash
# Immich
cd /home/brandon/projects/docker/immich-main
docker-compose up -d

# Jellyfin
cd /home/brandon/projects/docker/jellyfin
docker-compose up -d

# Romm
cd /home/brandon/projects/docker/romm
docker-compose up -d

# Outline
cd /home/brandon/projects/docker/outline
docker-compose up -d

# Others
cd /home/brandon/projects/docker/<service>
docker-compose up -d
```

## 📝 Notes

- **Immich** is the most critical service - it has had database corruption issues in the past
- All services have proper restart policies configured
- Backups are stored in `/home/brandon/backups/`
- Keep at least the last 3 backups for safety

