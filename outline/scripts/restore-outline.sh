#!/bin/bash

# Outline Restore Script
# Restores Outline from a backup created by backup-outline.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Outline Restore Script               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if backup path is provided
if [ -z "$1" ]; then
    echo -e "${RED}ERROR: No backup path provided${NC}"
    echo ""
    echo "Usage: $0 <backup_directory>"
    echo ""
    echo "Example: $0 /mnt/boston/media/backups/outline/20260119_143000"
    echo ""
    exit 1
fi

BACKUP_PATH="$1"

# Verify backup directory exists
if [ ! -d "$BACKUP_PATH" ]; then
    echo -e "${RED}ERROR: Backup directory does not exist: $BACKUP_PATH${NC}"
    exit 1
fi

# Verify backup files exist
if [ ! -f "$BACKUP_PATH/database.sql.gz" ]; then
    echo -e "${RED}ERROR: Database backup not found: $BACKUP_PATH/database.sql.gz${NC}"
    exit 1
fi

echo "Backup path: $BACKUP_PATH"
echo ""
echo -e "${YELLOW}WARNING: This will replace all current Outline data!${NC}"
echo -e "${YELLOW}Make sure you have a backup of the current state if needed.${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

echo ""

# Database credentials
DB_CONTAINER="outline_postgres"
DB_USER="outline"
DB_NAME="outline"

# 1. Stop Outline
echo -e "${YELLOW}[1/4] Stopping Outline...${NC}"
docker-compose stop outline
echo -e "${GREEN}✓ Outline stopped${NC}"
echo ""

# 2. Restore Database
echo -e "${YELLOW}[2/4] Restoring PostgreSQL database...${NC}"
# Drop and recreate database
docker exec $DB_CONTAINER psql -U $DB_USER -c "DROP DATABASE IF EXISTS $DB_NAME;"
docker exec $DB_CONTAINER psql -U $DB_USER -c "CREATE DATABASE $DB_NAME;"
# Restore from backup
gunzip -c "$BACKUP_PATH/database.sql.gz" | docker exec -i $DB_CONTAINER psql -U $DB_USER $DB_NAME
echo -e "${GREEN}✓ Database restored${NC}"
echo ""

# 3. Restore MinIO Storage
echo -e "${YELLOW}[3/4] Restoring MinIO storage...${NC}"
if [ -f "$BACKUP_PATH/minio-storage.tar.gz" ]; then
    # Backup current minio data
    if [ -d "./data/minio" ]; then
        mv ./data/minio ./data/minio.old.$(date +%s)
    fi
    # Restore from backup
    tar -xzf "$BACKUP_PATH/minio-storage.tar.gz" -C ./data/
    echo -e "${GREEN}✓ MinIO storage restored${NC}"
else
    echo -e "${YELLOW}⚠ MinIO backup not found, skipping${NC}"
fi
echo ""

# 4. Restart Outline
echo -e "${YELLOW}[4/4] Starting Outline...${NC}"
docker-compose up -d outline
echo -e "${GREEN}✓ Outline started${NC}"
echo ""

# Wait for health check
echo "Waiting for Outline to become healthy..."
sleep 10

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Restore Complete!                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Outline should now be accessible at: http://100.123.154.40:8000"
echo ""
echo "Check logs with: docker logs outline"

