#!/bin/bash
# Download YouTube video as full MP4 video
# Usage: ./download-video.sh "https://youtube.com/watch?v=..."

if [ -z "$1" ]; then
    echo "Usage: $0 <youtube-url>"
    echo "Example: $0 'https://youtube.com/watch?v=dQw4w9WgXcQ'"
    exit 1
fi

echo "Downloading full video: $1"
echo ""

# Use more robust format selection with fallbacks
# This will try multiple format combinations to avoid partial downloads
# Added options to bypass YouTube 403 errors:
# - Use default player client to avoid JS runtime issues
# - Add user agent to appear as a regular browser
# - Use slower download speed to avoid rate limiting
docker exec yt-dlp-web yt-dlp \
  --verbose \
  --extractor-args "youtube:player_client=default,web" \
  --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
  --format "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/bestvideo[ext=mp4]+bestaudio/best[ext=mp4]/best" \
  --merge-output-format mp4 \
  --add-metadata \
  --no-part \
  --no-mtime \
  --retries 10 \
  --fragment-retries 10 \
  --file-access-retries 10 \
  --extractor-retries 10 \
  --sleep-requests 1 \
  --sleep-interval 2 \
  --max-sleep-interval 5 \
  --output "/downloads/video/%(title)s.%(ext)s" \
  "$1"

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Download complete! Check: /mnt/boston/media/downloads/youtube/video/"
else
    echo "❌ Download failed with exit code: $EXIT_CODE"
    echo "Check the output above for errors."
    exit $EXIT_CODE
fi

