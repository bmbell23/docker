#!/bin/bash
# Helper script to download YouTube videos with proper metadata using yt-dlp
# Usage: ./download-with-metadata.sh "https://youtube.com/watch?v=..."

DOWNLOAD_DIR="/mnt/boston/media/downloads/youtube"

# Check if URL provided
if [ -z "$1" ]; then
    echo "Usage: $0 <youtube-url>"
    echo "Example: $0 'https://youtube.com/watch?v=dQw4w9WgXcQ'"
    exit 1
fi

# Run yt-dlp with metadata options
docker run --rm -v "$DOWNLOAD_DIR:/downloads" \
    jauderho/yt-dlp:latest \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 0 \
    --embed-thumbnail \
    --add-metadata \
    --parse-metadata "%(title)s:%(meta_title)s" \
    --parse-metadata "%(uploader)s:%(meta_artist)s" \
    --output "/downloads/%(title)s.%(ext)s" \
    "$1"

echo ""
echo "✅ Download complete! File saved to: $DOWNLOAD_DIR"
echo ""
echo "To tag and organize with beets:"
echo "  beet import $DOWNLOAD_DIR"

