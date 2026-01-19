#!/bin/bash
# Outline Setup Script
# This script helps you set up Outline with proper configuration

set -e

echo "========================================="
echo "  Outline Wiki Setup"
echo "========================================="
echo ""

# Check if docker and docker-compose are installed
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Error: Docker Compose is not installed"
    exit 1
fi

echo "✅ Docker and Docker Compose are installed"
echo ""

# Generate secret keys
echo "📝 Generating secret keys..."
SECRET_KEY=$(openssl rand -hex 32)
UTILS_SECRET=$(openssl rand -hex 32)
echo "✅ Secret keys generated"
echo ""

# Get server IP
echo "🌐 Server Configuration"
read -p "Enter your server IP address [100.123.154.40]: " SERVER_IP
SERVER_IP=${SERVER_IP:-100.123.154.40}
echo ""

# Get passwords
echo "🔐 Database Configuration"
read -sp "Enter PostgreSQL password (or press Enter for auto-generated): " POSTGRES_PASSWORD
echo ""
if [ -z "$POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD=$(openssl rand -hex 16)
    echo "✅ Auto-generated PostgreSQL password"
fi

read -sp "Enter MinIO password (or press Enter for auto-generated): " MINIO_PASSWORD
echo ""
if [ -z "$MINIO_PASSWORD" ]; then
    MINIO_PASSWORD=$(openssl rand -hex 16)
    echo "✅ Auto-generated MinIO password"
fi
echo ""

# Update docker-compose.yml
echo "📝 Updating docker-compose.yml..."
sed -i "s|SECRET_KEY:.*|SECRET_KEY: $SECRET_KEY|g" docker-compose.yml
sed -i "s|UTILS_SECRET:.*|UTILS_SECRET: $UTILS_SECRET|g" docker-compose.yml
sed -i "s|POSTGRES_PASSWORD:.*|POSTGRES_PASSWORD: $POSTGRES_PASSWORD|g" docker-compose.yml
sed -i "s|outline_password_change_me|$POSTGRES_PASSWORD|g" docker-compose.yml
sed -i "s|MINIO_ROOT_PASSWORD:.*|MINIO_ROOT_PASSWORD: $MINIO_PASSWORD|g" docker-compose.yml
sed -i "s|minio_password_change_me|$MINIO_PASSWORD|g" docker-compose.yml
sed -i "s|URL:.*|URL: http://$SERVER_IP:3000|g" docker-compose.yml
sed -i "s|AWS_S3_UPLOAD_BUCKET_URL:.*|AWS_S3_UPLOAD_BUCKET_URL: http://$SERVER_IP:9000|g" docker-compose.yml
echo "✅ docker-compose.yml updated"
echo ""

# Save credentials
echo "💾 Saving credentials to .env file..."
cat > .env << EOF
# Outline Configuration
# Generated on $(date)

SECRET_KEY=$SECRET_KEY
UTILS_SECRET=$UTILS_SECRET
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
MINIO_ROOT_PASSWORD=$MINIO_PASSWORD
SERVER_IP=$SERVER_IP

# MinIO Console: http://$SERVER_IP:9001
# MinIO Username: minio_admin
# MinIO Password: $MINIO_PASSWORD

# Outline URL: http://$SERVER_IP:3000
EOF
echo "✅ Credentials saved to .env"
echo ""

# Start MinIO first
echo "🚀 Starting MinIO..."
docker compose up -d outline-minio
echo "⏳ Waiting for MinIO to be ready..."
sleep 15
echo "✅ MinIO started"
echo ""

# Create MinIO bucket
echo "📦 Creating MinIO bucket..."
echo "Please create a bucket named 'outline' in MinIO:"
echo "1. Open http://$SERVER_IP:9001 in your browser"
echo "2. Login with username: minio_admin"
echo "3. Login with password: $MINIO_PASSWORD"
echo "4. Click 'Buckets' → 'Create Bucket'"
echo "5. Name it 'outline' and click 'Create Bucket'"
echo ""
read -p "Press Enter once you've created the bucket..."
echo ""

# Start all services
echo "🚀 Starting all Outline services..."
docker compose up -d
echo "✅ All services started"
echo ""

# Show status
echo "📊 Container Status:"
docker compose ps
echo ""

echo "========================================="
echo "  ✅ Outline Setup Complete!"
echo "========================================="
echo ""
echo "📝 Important Information:"
echo ""
echo "Outline URL:    http://$SERVER_IP:3000"
echo "MinIO Console:  http://$SERVER_IP:9001"
echo "MinIO Username: minio_admin"
echo "MinIO Password: $MINIO_PASSWORD"
echo ""
echo "Credentials saved in: .env"
echo ""
echo "📚 Next Steps:"
echo "1. Wait 1-2 minutes for Outline to complete database migration"
echo "2. Check logs: docker compose logs -f outline"
echo "3. Access Outline at http://$SERVER_IP:3000"
echo "4. Configure authentication (see README.md)"
echo ""
echo "🔧 Useful Commands:"
echo "  View logs:    docker compose logs -f outline"
echo "  Restart:      docker compose restart"
echo "  Stop:         docker compose down"
echo "  Update:       docker compose pull && docker compose up -d"
echo ""

