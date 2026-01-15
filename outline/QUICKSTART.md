# Outline Quick Start Guide

Get Outline up and running in 5 minutes!

## Option 1: Automated Setup (Recommended)

```bash
cd ~/projects/docker/outline
./setup.sh
```

The script will:
- Generate secure random keys
- Configure all services
- Start MinIO
- Guide you through bucket creation
- Start Outline

## Option 2: Manual Setup

### Step 1: Generate Keys

```bash
# Generate two secret keys
openssl rand -hex 32  # Copy this for SECRET_KEY
openssl rand -hex 32  # Copy this for UTILS_SECRET
```

### Step 2: Edit docker-compose.yml

Replace these values in `docker-compose.yml`:
- `SECRET_KEY`: Paste first generated key
- `UTILS_SECRET`: Paste second generated key
- `POSTGRES_PASSWORD`: Change to a secure password
- `MINIO_ROOT_PASSWORD`: Change to a secure password
- `URL`: Update to your server IP (e.g., `http://192.168.1.100:3000`)
- `AWS_S3_UPLOAD_BUCKET_URL`: Update to your server IP (e.g., `http://192.168.1.100:9000`)

### Step 3: Start MinIO

```bash
docker compose up -d outline-minio
```

### Step 4: Create MinIO Bucket

1. Open http://your-server-ip:9001
2. Login:
   - Username: `minio_admin`
   - Password: (from docker-compose.yml)
3. Click "Buckets" → "Create Bucket"
4. Name: `outline`
5. Click "Create Bucket"

### Step 5: Start All Services

```bash
docker compose up -d
```

### Step 6: Wait for Migration

```bash
# Watch the logs
docker compose logs -f outline

# Wait for: "Listening on http://0.0.0.0:3000"
```

### Step 7: Access Outline

Open http://your-server-ip:3000

## Troubleshooting

### Outline won't start
```bash
# Check logs
docker compose logs outline

# Common issues:
# - MinIO bucket not created → Create "outline" bucket
# - Secret keys too short → Must be at least 32 characters
# - Database not ready → Wait 30 seconds and try again
```

### Can't access Outline
```bash
# Check if container is running
docker compose ps

# Check if port is accessible
curl http://localhost:3000

# Check firewall
sudo ufw status
```

### Database migration stuck
```bash
# Restart the migration
docker compose down
docker compose up -d
```

## Next Steps

1. **Set up authentication** - See README.md for SMTP/OAuth setup
2. **Create your first document** - Start writing!
3. **Invite team members** - Share the URL
4. **Customize settings** - Explore Outline settings

## Useful Commands

```bash
# View logs
docker compose logs -f outline

# Restart services
docker compose restart

# Stop everything
docker compose down

# Update Outline
docker compose pull
docker compose up -d

# Backup database
docker compose exec outline-postgres pg_dump -U outline outline > backup.sql

# Restore database
docker compose exec -T outline-postgres psql -U outline outline < backup.sql
```

## Default Ports

- **3000** - Outline web interface
- **9000** - MinIO S3 API
- **9001** - MinIO web console

## Security Notes

⚠️ **Important**: This setup is configured for local network use without SSL.

For production use:
1. Set up a reverse proxy (nginx/Traefik) with SSL
2. Configure proper authentication (SMTP/OAuth/OIDC)
3. Use strong passwords for all services
4. Regularly backup your data
5. Keep Outline updated

## Getting Help

- 📖 [Full README](README.md)
- 🐛 [Troubleshooting Guide](../immich-main/TROUBLESHOOTING.md)
- 🌐 [Outline Docs](https://docs.getoutline.com/)
- 💬 [Outline GitHub](https://github.com/outline/outline)

