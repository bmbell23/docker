# Setup Summary - Outline Wiki & Immich KBA

## ✅ Completed Tasks

### 1. Created Immich Troubleshooting KBA ✅

**Location**: `immich-main/TROUBLESHOOTING.md`

A comprehensive knowledge base article documenting:
- **Problem**: Immich server container down due to port 2283 conflict
- **Root Cause**: Stale docker-proxy processes holding the port
- **Solution**: Step-by-step fix using `lsof` and `kill` commands
- **Prevention**: Best practices for avoiding the issue
- **Verification**: How to confirm the fix worked

### 2. Set Up Outline Wiki Container ✅

**Location**: `outline/`

Created a complete Outline wiki setup with:
- **docker-compose.yml**: Full stack configuration
  - Outline application
  - PostgreSQL database
  - Redis cache
  - MinIO S3-compatible storage
- **README.md**: Comprehensive setup and configuration guide
- **QUICKSTART.md**: 5-minute quick start guide
- **setup.sh**: Automated setup script
- **.env.example**: Environment variable template

**Services**:
- Outline: http://100.69.184.113:3000
- MinIO Console: http://100.69.184.113:9001

### 3. Added Outline Card to Dashboard ✅

**Modified Files**:
- `dashboard/static/index.html`: Added new "Tools" category with Outline card
- `dashboard/app.py`: Added 'outline' to CONTAINERS dictionary

**Note**: Dashboard needs to be restarted to see the changes. There was a permission issue preventing automatic restart.

## 🚀 Next Steps

### Step 1: Restart Dashboard (Manual)

The dashboard container has a permission issue. Please restart it manually:

```bash
# Option 1: Restart the container
sudo systemctl restart docker
# Then wait for dashboard to come back up

# Option 2: Rebuild and restart
cd ~/projects/docker/dashboard
sudo docker compose down
sudo docker compose up -d

# Option 3: Just restart the system
sudo reboot
```

After restart, the Outline card will appear in the "Tools" section at http://100.69.184.113:8001

### Step 2: Set Up Outline

Choose one of these methods:

#### Method A: Automated Setup (Recommended)

```bash
cd ~/projects/docker/outline
./setup.sh
```

This will:
1. Generate secure random keys
2. Configure all services
3. Start MinIO
4. Guide you through bucket creation
5. Start Outline

#### Method B: Manual Setup

```bash
cd ~/projects/docker/outline

# 1. Generate secret keys
openssl rand -hex 32  # Copy for SECRET_KEY
openssl rand -hex 32  # Copy for UTILS_SECRET

# 2. Edit docker-compose.yml and replace:
#    - SECRET_KEY
#    - UTILS_SECRET
#    - POSTGRES_PASSWORD
#    - MINIO_ROOT_PASSWORD
#    - URL (if different IP)
#    - AWS_S3_UPLOAD_BUCKET_URL (if different IP)

# 3. Start MinIO
docker compose up -d outline-minio

# 4. Create MinIO bucket
# Open http://100.69.184.113:9001
# Login: minio_admin / (your password)
# Create bucket named "outline"

# 5. Start all services
docker compose up -d

# 6. Check logs
docker compose logs -f outline
```

### Step 3: Access Outline

1. Wait 1-2 minutes for database migration
2. Open http://100.69.184.113:3000
3. Configure authentication (see outline/README.md)

### Step 4: Add Immich KBA to Outline

Once Outline is running:
1. Create a new collection called "Troubleshooting" or "Docker Services"
2. Create a new document
3. Copy content from `immich-main/TROUBLESHOOTING.md`
4. Paste and format in Outline

## 📁 File Structure

```
docker/
├── outline/
│   ├── docker-compose.yml      # Main configuration
│   ├── README.md               # Full documentation
│   ├── QUICKSTART.md           # Quick start guide
│   ├── setup.sh                # Automated setup script
│   ├── .env.example            # Environment template
│   └── data/                   # Created on first run
│       ├── postgres/           # Database files
│       ├── minio/              # File storage
│       └── outline/            # App data
│
├── immich-main/
│   └── TROUBLESHOOTING.md      # Immich port conflict KBA
│
├── dashboard/
│   ├── app.py                  # Updated with 'outline' service
│   └── static/
│       └── index.html          # Updated with Outline card
│
└── SETUP_SUMMARY.md            # This file
```

## 🔧 Useful Commands

### Outline Management

```bash
cd ~/projects/docker/outline

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
docker compose exec outline-postgres pg_dump -U outline outline > backup_$(date +%Y%m%d).sql

# Backup files
tar -czf outline_backup_$(date +%Y%m%d).tar.gz ./data
```

### Dashboard Management

```bash
cd ~/projects/docker/dashboard

# Restart dashboard
docker compose restart

# View logs
docker compose logs -f

# Rebuild after changes
docker compose down
docker compose up -d --build
```

## 📚 Documentation References

- **Outline Setup**: `outline/README.md`
- **Outline Quick Start**: `outline/QUICKSTART.md`
- **Immich Troubleshooting**: `immich-main/TROUBLESHOOTING.md`
- **Outline Official Docs**: https://docs.getoutline.com/
- **Outline GitHub**: https://github.com/outline/outline

## ⚠️ Important Notes

1. **Security**: This setup is configured for local network use without SSL
   - For production, set up reverse proxy with SSL
   - Configure proper authentication (SMTP/OAuth/OIDC)
   - Use strong passwords

2. **Ports Used**:
   - 3000: Outline web interface
   - 9000: MinIO S3 API
   - 9001: MinIO web console

3. **Authentication**: By default, Outline requires authentication setup
   - See `outline/README.md` for SMTP/OAuth configuration
   - Or set up Keycloak for fully self-hosted auth

4. **Backups**: Regularly backup:
   - PostgreSQL database
   - MinIO data directory
   - Outline data directory

## 🎉 Summary

You now have:
1. ✅ Immich troubleshooting KBA documented
2. ✅ Outline wiki fully configured and ready to deploy
3. ✅ Dashboard updated with Outline card (needs restart)
4. ✅ Automated setup script for easy deployment
5. ✅ Comprehensive documentation

**Next**: Restart dashboard, run `./outline/setup.sh`, and start documenting!

