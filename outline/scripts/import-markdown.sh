#!/bin/bash

# Outline Markdown Import Script
# This script imports markdown files into Outline using the API

set -e

# Configuration
OUTLINE_URL="http://100.123.154.40:8000"
API_TOKEN=""  # You'll need to generate this from Outline Settings → API Tokens
COLLECTION_NAME="Imported Notes"
SOURCE_DIR="/mnt/boston/media/notes"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Outline Markdown Import Script${NC}"
echo "================================"
echo ""

# Check if API token is set
if [ -z "$API_TOKEN" ]; then
    echo -e "${RED}ERROR: API_TOKEN is not set!${NC}"
    echo ""
    echo "To generate an API token:"
    echo "1. Log into Outline at $OUTLINE_URL"
    echo "2. Go to Settings → API Tokens"
    echo "3. Click 'Create a token'"
    echo "4. Copy the token and set it in this script"
    echo ""
    exit 1
fi

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${YELLOW}WARNING: Source directory does not exist: $SOURCE_DIR${NC}"
    echo "Creating directory..."
    mkdir -p "$SOURCE_DIR"
fi

# Find or create collection
echo "Finding or creating collection: $COLLECTION_NAME"
COLLECTION_ID=$(curl -s -X POST "$OUTLINE_URL/api/collections.list" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    | jq -r ".data[] | select(.name==\"$COLLECTION_NAME\") | .id" | head -1)

if [ -z "$COLLECTION_ID" ]; then
    echo "Collection not found, creating new collection..."
    COLLECTION_ID=$(curl -s -X POST "$OUTLINE_URL/api/collections.create" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$COLLECTION_NAME\",\"description\":\"Imported markdown files\"}" \
        | jq -r '.data.id')
    echo -e "${GREEN}Created collection with ID: $COLLECTION_ID${NC}"
else
    echo -e "${GREEN}Found existing collection with ID: $COLLECTION_ID${NC}"
fi

# Import markdown files
echo ""
echo "Importing markdown files from: $SOURCE_DIR"
echo ""

count=0
for file in "$SOURCE_DIR"/*.md; do
    if [ -f "$file" ]; then
        filename=$(basename "$file" .md)
        echo -n "Importing: $filename ... "
        
        # Read file content
        content=$(cat "$file")
        
        # Create document
        response=$(curl -s -X POST "$OUTLINE_URL/api/documents.create" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{
                \"title\":\"$filename\",
                \"text\":$(echo "$content" | jq -Rs .),
                \"collectionId\":\"$COLLECTION_ID\",
                \"publish\":true
            }")
        
        if echo "$response" | jq -e '.data.id' > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
            ((count++))
        else
            echo -e "${RED}✗${NC}"
            echo "Error: $(echo "$response" | jq -r '.message // "Unknown error"')"
        fi
    fi
done

echo ""
echo -e "${GREEN}Import complete! Imported $count files.${NC}"

