#!/bin/bash

# Script to check for missing video files referenced in Immich logs
echo "Checking for missing video files..."

# Get recent logs and extract missing file paths
docker logs immich_server --since 24h 2>&1 | \
grep -E "ENOENT.*\.MOV|ENOENT.*\.mp4|ENOENT.*\.avi|ENOENT.*\.mkv" | \
sed -n "s/.*access '\([^']*\)'.*/\1/p" | \
sort | uniq > /tmp/missing_videos.txt

if [ -s /tmp/missing_videos.txt ]; then
    echo "Found missing video files:"
    while read -r file; do
        echo "Missing: $file"
        # Check if file exists in a different location
        basename_file=$(basename "$file")
        echo "  Searching for $basename_file in media directory..."
        find /mnt/boston/media/pictures -name "$basename_file" -type f 2>/dev/null | head -3
        echo ""
    done < /tmp/missing_videos.txt
else
    echo "No missing video files found in recent logs."
fi

# Check for video files with potential issues
echo "Checking for video files that might have transcoding issues..."
find /mnt/boston/media/pictures -name "*.MOV" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" | \
head -10 | while read -r video; do
    if [ -f "$video" ]; then
        size=$(stat -c%s "$video" 2>/dev/null || echo "0")
        if [ "$size" -eq 0 ]; then
            echo "Zero-size video file: $video"
        fi
    fi
done

rm -f /tmp/missing_videos.txt
echo "Check complete."
