# Outline Wiki - Self-Hosted Setup

Outline is a modern, fast, and collaborative knowledge base for your team. This setup includes all necessary services running in Docker containers.

## 🏗️ Architecture

This setup includes:
- **Outline**: The main wiki application
- **PostgreSQL**: Database for storing wiki data
- **Redis**: Cache and session storage
- **MinIO**: S3-compatible object storage for file uploads

## 📋 Prerequisites

- Docker and Docker Compose installed
- At least 2GB of free RAM
- Ports 3000, 9000, and 9001 available

## 🚀 Quick Start

### 1. Generate Secret Keys

Generate two random secret keys (minimum 32 characters each):

```bash
# Generate SECRET_KEY
openssl rand -hex 32

# Generate UTILS_SECRET
openssl rand -hex 32
```

### 2. Update docker-compose.yml

Edit `docker-compose.yml` and update the following:

- `SECRET_KEY`: Replace with the first generated key
- `UTILS_SECRET`: Replace with the second generated key
- `POSTGRES_PASSWORD`: Change from default
- `MINIO_ROOT_PASSWORD`: Change from default
- `URL`: Update to your server's IP address (currently set to `http://100.123.154.40:3000`)
- `AWS_S3_UPLOAD_BUCKET_URL`: Update to your server's IP (currently `http://100.123.154.40:9000`)

### 3. Create MinIO Bucket

Before starting Outline, you need to create the S3 bucket in MinIO:

```bash
# Start only MinIO first
docker compose up -d outline-minio

# Wait for MinIO to be ready (about 10 seconds)
sleep 10

# Access MinIO console at http://your-server-ip:9001
# Login with:
#   Username: minio_admin
#   Password: (the password you set in docker-compose.yml)

# Create a bucket named "outline" with private access
```

**Via MinIO Console:**
1. Go to http://100.123.154.40:9001
2. Login with credentials from docker-compose.yml
3. Click "Buckets" → "Create Bucket"
4. Name it `outline`
5. Click "Create Bucket"

**Via MinIO Client (mc):**
```bash
# Install mc if not already installed
docker run --rm -it --entrypoint=/bin/sh minio/mc

# Configure mc
mc alias set myminio http://100.123.154.40:9000 minio_admin minio_password_change_me

# Create bucket
mc mb myminio/outline

# Set bucket policy to private
mc anonymous set none myminio/outline
```

### 4. Start All Services

```bash
# Start all services
docker compose up -d

# Check logs
docker compose logs -f outline

# Wait for database migration to complete
# You should see "Listening on http://0.0.0.0:3000"
```

### 5. Access Outline

Open your browser and navigate to:
```
http://100.123.154.40:3000
```

## 🔐 Authentication Setup

By default, this setup doesn't include authentication. You have several options:

### Option 1: Email Authentication (Recommended for local use)

Uncomment the SMTP section in `docker-compose.yml` and configure with your email provider:

```yaml
SMTP_HOST: smtp.gmail.com
SMTP_PORT: 587
SMTP_USERNAME: your-email@gmail.com
SMTP_PASSWORD: your-app-password
SMTP_FROM_EMAIL: your-email@gmail.com
```

### Option 2: Slack/Google OAuth

Configure Slack or Google OAuth by uncommenting and filling in the respective sections in `docker-compose.yml`.

### Option 3: Keycloak (Advanced)

For a fully self-hosted authentication solution, you can set up Keycloak. See the [Keycloak setup guide](https://blog.gurucomputing.com.au/s/blog/doc/installing-outline-tXZO9ehoFV).

## 📁 Data Storage

All data is stored in the `./data` directory:
- `./data/postgres` - Database files
- `./data/minio` - Uploaded files and images
- `./data/outline` - Application data

## 🔧 Maintenance

### View Logs
```bash
docker compose logs -f outline
```

### Restart Services
```bash
docker compose restart
```

### Backup Data
```bash
# Backup database
docker compose exec outline-postgres pg_dump -U outline outline > backup_$(date +%Y%m%d).sql

# Backup MinIO data
tar -czf minio_backup_$(date +%Y%m%d).tar.gz ./data/minio
```

### Update Outline
```bash
docker compose pull
docker compose up -d
```

## 🐛 Troubleshooting

### Outline won't start
- Check logs: `docker compose logs outline`
- Ensure MinIO bucket "outline" exists
- Verify all secret keys are set and at least 32 characters
- Check that PostgreSQL is healthy: `docker compose ps`

### Can't upload files
- Verify MinIO is running: `docker compose ps outline-minio`
- Check MinIO bucket exists and is accessible
- Verify `AWS_S3_UPLOAD_BUCKET_URL` matches your server IP

### Database migration errors
- Stop all services: `docker compose down`
- Remove database volume: `rm -rf ./data/postgres`
- Start fresh: `docker compose up -d`

## 📚 Resources

- [Outline Documentation](https://docs.getoutline.com/)
- [Outline GitHub](https://github.com/outline/outline)
- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)

