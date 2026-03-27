#!/bin/bash
# Download YouTube video as MP3 audio
# Usage: ./download-mp3.sh "https://youtube.com/watch?v=..."

if [ -z "$1" ]; then
    echo "Usage: $0 <youtube-url>"
    echo "Example: $0 'https://youtube.com/watch?v=dQw4w9WgXcQ'"
    exit 1
fi

echo "Downloading as MP3: $1"
docker exec yt-dlp-web yt-dlp \
  --extract-audio \
  --audio-format mp3 \
  --audio-quality 0 \
  --embed-thumbnail \
  --add-metadata \
  --parse-metadata '%(title)s:%(meta_title)s' \
  --parse-metadata '%(uploader)s:%(meta_artist)s' \
  --output "/downloads/music/%(title)s.%(ext)s" \
  "$1"

echo ""
echo "Download complete! Check: /mnt/boston/media/downloads/youtube/music/"

