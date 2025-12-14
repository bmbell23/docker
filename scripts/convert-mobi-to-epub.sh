#!/bin/bash

# Mobi to EPUB Converter Script
# Recursively finds .mobi files and converts them to .epub using Calibre's ebook-convert

# Don't use set -e because the while read loop returns non-zero when it finishes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories to scan
SCAN_DIRS=(
    "/mnt/boston/media/downloads/torrents"
    "/mnt/boston/media/books"
)

# Counter variables
TOTAL_FOUND=0
TOTAL_CONVERTED=0
TOTAL_SKIPPED=0
TOTAL_FAILED=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Mobi to EPUB Converter${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if ebook-convert is available
USE_CALIBRE_WEB=false
CLEANUP_CONTAINER=false

if ! command -v ebook-convert &> /dev/null; then
    echo -e "${YELLOW}ebook-convert not found on host, using Docker container...${NC}"

    # Try to use the calibre-web container's ebook-convert
    if docker ps | grep -q calibre-web; then
        echo -e "${GREEN}✓ Using ebook-convert from calibre-web container${NC}"
        CONVERT_CMD="docker exec calibre-web ebook-convert"
        USE_CALIBRE_WEB=true
    else
        echo -e "${YELLOW}Calibre-web container not running. Starting temporary container...${NC}"
        docker run -d --name mobi-converter \
            -v /mnt/boston/media:/media \
            -e DOCKER_MODS=linuxserver/mods:universal-calibre \
            lscr.io/linuxserver/calibre-web:latest sleep 600 > /dev/null 2>&1

        echo "Waiting 90 seconds for Calibre to install..."
        sleep 90

        CONVERT_CMD="docker exec mobi-converter ebook-convert"
        CLEANUP_CONTAINER=true
    fi
else
    CONVERT_CMD="ebook-convert"
fi

echo ""
echo -e "${BLUE}Scanning directories for .mobi files...${NC}"
echo ""

# Function to convert a single mobi file
convert_mobi() {
    local mobi_file="$1"
    local epub_file="${mobi_file%.mobi}.epub"

    # Check if EPUB already exists
    if [ -f "$epub_file" ]; then
        echo -e "${YELLOW}⊘ SKIP:${NC} ${mobi_file##*/}"
        echo -e "   ${YELLOW}(EPUB already exists)${NC}"
        ((TOTAL_SKIPPED++))
        return
    fi

    echo -e "${BLUE}→ Converting:${NC} ${mobi_file##*/}"

    # Determine container paths based on which directory the file is in
    local container_mobi=""
    local container_epub=""

    if [[ "$mobi_file" == /mnt/boston/media/books/* ]]; then
        # File is in books directory - mounted as /books in calibre-web container
        container_mobi="/books${mobi_file#/mnt/boston/media/books}"
        container_epub="/books${epub_file#/mnt/boston/media/books}"
    elif [[ "$mobi_file" == /mnt/boston/media/downloads/* ]]; then
        # File is in downloads directory - NOT mounted in calibre-web container!
        # We need to use the temporary container with /media mount
        if [ "$USE_CALIBRE_WEB" = true ]; then
            echo -e "${YELLOW}⊘ SKIP:${NC} ${mobi_file##*/}"
            echo -e "   ${YELLOW}(File not accessible in calibre-web container)${NC}"
            echo -e "   ${YELLOW}Creating temporary container for downloads...${NC}"

            # Switch to temporary container
            docker run -d --name mobi-converter \
                -v /mnt/boston/media:/media \
                -e DOCKER_MODS=linuxserver/mods:universal-calibre \
                lscr.io/linuxserver/calibre-web:latest sleep 600 > /dev/null 2>&1

            echo "   Waiting 90 seconds for Calibre to install..."
            sleep 90

            CONVERT_CMD="docker exec mobi-converter ebook-convert"
            USE_CALIBRE_WEB=false
            CLEANUP_CONTAINER=true
        fi

        container_mobi="/media${mobi_file#/mnt/boston/media}"
        container_epub="/media${epub_file#/mnt/boston/media}"
    else
        echo -e "${RED}✗ ERROR:${NC} Unknown path: $mobi_file"
        ((TOTAL_FAILED++))
        return
    fi

    # Convert the file
    if $CONVERT_CMD "$container_mobi" "$container_epub" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ SUCCESS:${NC} ${epub_file##*/}"
        ((TOTAL_CONVERTED++))
    else
        echo -e "${RED}✗ FAILED:${NC} ${mobi_file##*/}"
        ((TOTAL_FAILED++))
    fi

    echo ""
}

# Scan each directory
for scan_dir in "${SCAN_DIRS[@]}"; do
    if [ ! -d "$scan_dir" ]; then
        echo -e "${YELLOW}Warning: Directory not found: $scan_dir${NC}"
        continue
    fi

    echo -e "${BLUE}Scanning: $scan_dir${NC}"

    # Find all .mobi files (case-insensitive)
    while IFS= read -r -d '' mobi_file; do
        ((TOTAL_FOUND++))
        convert_mobi "$mobi_file"
    done < <(find "$scan_dir" -type f -iname "*.mobi" -print0)
done

# Cleanup temporary container if created
if [ "$CLEANUP_CONTAINER" = true ]; then
    echo -e "${BLUE}Cleaning up temporary container...${NC}"
    docker stop mobi-converter > /dev/null 2>&1
    docker rm mobi-converter > /dev/null 2>&1
fi

# Print summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Conversion Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total .mobi files found: ${YELLOW}$TOTAL_FOUND${NC}"
echo -e "Successfully converted:  ${GREEN}$TOTAL_CONVERTED${NC}"
echo -e "Skipped (EPUB exists):   ${YELLOW}$TOTAL_SKIPPED${NC}"
echo -e "Failed:                  ${RED}$TOTAL_FAILED${NC}"
echo ""

if [ $TOTAL_CONVERTED -gt 0 ]; then
    echo -e "${GREEN}✓ Conversion complete!${NC}"
    echo -e "${BLUE}Tip: Rescan your Kavita library to see the new EPUB files${NC}"
fi

