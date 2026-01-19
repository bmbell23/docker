#!/bin/bash

# Outline Backup Script
# Backs up PostgreSQL database, MinIO storage, and exports all documents as Markdown

set -e

# Configuration
BACKUP_DIR="/mnt/boston/media/backups/outline"
OUTLINE_URL="http://100.123.154.40:8000"
API_TOKEN=""  # Set this to your Outline API token for markdown exports
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

# Database credentials (from docker-compose.yml)
DB_CONTAINER="outline_postgres"
DB_USER="outline"
DB_NAME="outline"
DB_PASSWORD="outline_password_change_me"

# MinIO/Storage
MINIO_DATA_DIR="./data/minio"
POSTGRES_DATA_DIR="./data/postgres"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Outline Backup Script                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Backup timestamp: $TIMESTAMP"
echo "Backup location: $BACKUP_PATH"
echo ""

# Create backup directory
mkdir -p "$BACKUP_PATH"

# 1. Backup PostgreSQL Database
echo -e "${YELLOW}[1/4] Backing up PostgreSQL database...${NC}"
docker exec $DB_CONTAINER pg_dump -U $DB_USER $DB_NAME | gzip > "$BACKUP_PATH/database.sql.gz"
echo -e "${GREEN}✓ Database backup complete: $(du -h "$BACKUP_PATH/database.sql.gz" | cut -f1)${NC}"
echo ""

# 2. Backup MinIO Storage (attachments, images, etc.)
echo -e "${YELLOW}[2/4] Backing up MinIO storage...${NC}"
if [ -d "$MINIO_DATA_DIR" ]; then
    tar -czf "$BACKUP_PATH/minio-storage.tar.gz" -C "$(dirname "$MINIO_DATA_DIR")" "$(basename "$MINIO_DATA_DIR")"
    echo -e "${GREEN}✓ MinIO storage backup complete: $(du -h "$BACKUP_PATH/minio-storage.tar.gz" | cut -f1)${NC}"
else
    echo -e "${RED}✗ MinIO data directory not found: $MINIO_DATA_DIR${NC}"
fi
echo ""

# 3. Backup Docker Compose Configuration
echo -e "${YELLOW}[3/4] Backing up configuration...${NC}"
cp docker-compose.yml "$BACKUP_PATH/docker-compose.yml"
echo -e "${GREEN}✓ Configuration backup complete${NC}"
echo ""

# 4. Export all documents as Markdown (optional, requires API token)
echo -e "${YELLOW}[4/4] Exporting documents as Markdown...${NC}"
if [ -z "$API_TOKEN" ]; then
    echo -e "${YELLOW}⚠ API_TOKEN not set, skipping markdown export${NC}"
    echo "  To enable markdown exports, set API_TOKEN in this script"
else
    MARKDOWN_DIR="$BACKUP_PATH/markdown-export"
    mkdir -p "$MARKDOWN_DIR"
    
    # Get all collections
    collections=$(curl -s -X POST "$OUTLINE_URL/api/collections.list" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.data[].id')
    
    doc_count=0
    for collection_id in $collections; do
        # Get collection name
        collection_name=$(curl -s -X POST "$OUTLINE_URL/api/collections.info" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"id\":\"$collection_id\"}" | jq -r '.data.name')
        
        # Create collection directory
        collection_dir="$MARKDOWN_DIR/$collection_name"
        mkdir -p "$collection_dir"
        
        # Get all documents in collection
        documents=$(curl -s -X POST "$OUTLINE_URL/api/documents.list" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"collectionId\":\"$collection_id\"}" | jq -r '.data[].id')
        
        for doc_id in $documents; do
            # Get document details
            doc_info=$(curl -s -X POST "$OUTLINE_URL/api/documents.info" \
                -H "Authorization: Bearer $API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"id\":\"$doc_id\"}")
            
            doc_title=$(echo "$doc_info" | jq -r '.data.title' | sed 's/[^a-zA-Z0-9 -]/_/g')
            doc_text=$(echo "$doc_info" | jq -r '.data.text')
            
            # Save as markdown
            echo "$doc_text" > "$collection_dir/${doc_title}.md"
            ((doc_count++))
        done
    done
    
    echo -e "${GREEN}✓ Exported $doc_count documents as Markdown${NC}"
fi
echo ""

# Create backup summary
cat > "$BACKUP_PATH/backup-info.txt" << EOF
Outline Backup Summary
======================
Timestamp: $TIMESTAMP
Date: $(date)

Contents:
- database.sql.gz: PostgreSQL database dump
- minio-storage.tar.gz: MinIO object storage (attachments, images)
- docker-compose.yml: Docker Compose configuration
- markdown-export/: All documents exported as Markdown (if API token was set)

Restore Instructions:
1. Stop Outline: docker-compose down
2. Restore database: gunzip -c database.sql.gz | docker exec -i outline_postgres psql -U outline outline
3. Restore MinIO: tar -xzf minio-storage.tar.gz -C ./data/
4. Start Outline: docker-compose up -d
EOF

# Calculate total backup size
total_size=$(du -sh "$BACKUP_PATH" | cut -f1)

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Backup Complete!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Total backup size: $total_size"
echo "Backup location: $BACKUP_PATH"
echo ""
echo "To restore from this backup, see: $BACKUP_PATH/backup-info.txt"

