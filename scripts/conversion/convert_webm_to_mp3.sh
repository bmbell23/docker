#!/bin/bash

# Convert all .webm files in music directory to .mp3
# This uses ffmpeg in a Docker container

MUSIC_DIR="/mnt/boston/media/music"

echo "Finding .webm files in $MUSIC_DIR..."

find "$MUSIC_DIR" -type f -name "*.webm" | while read -r webm_file; do
    # Get the output filename (replace .webm with .mp3)
    mp3_file="${webm_file%.webm}.mp3"
    
    # Skip if mp3 already exists
    if [ -f "$mp3_file" ]; then
        echo "Skipping (already exists): $mp3_file"
        continue
    fi
    
    echo "Converting: $webm_file"
    
    # Use ffmpeg Docker container to convert
    docker run --rm \
        -v "$MUSIC_DIR:/music" \
        linuxserver/ffmpeg:latest \
        -i "/music/${webm_file#$MUSIC_DIR/}" \
        -vn \
        -ar 44100 \
        -ac 2 \
        -b:a 192k \
        "/music/${mp3_file#$MUSIC_DIR/}"
    
    if [ $? -eq 0 ]; then
        echo "✓ Created: $mp3_file"
        # Optionally delete the .webm file after successful conversion
        # Uncomment the next line if you want to auto-delete .webm files
        # rm "$webm_file"
    else
        echo "✗ Failed: $webm_file"
    fi
done

echo ""
echo "Done! Triggering Jellyfin rescan..."
docker exec jellyfin curl -X POST "http://localhost:8096/Library/Refresh" -H "X-Emby-Token: YOUR_API_KEY" 2>/dev/null || echo "Note: You may need to manually rescan in Jellyfin"

