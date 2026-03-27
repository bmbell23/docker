#!/bin/bash
# Test video download with detailed diagnostics
# Usage: ./test-download.sh "https://youtube.com/watch?v=..."

if [ -z "$1" ]; then
    echo "Usage: $0 <youtube-url>"
    echo "Example: $0 'https://youtube.com/watch?v=dQw4w9WgXcQ'"
    exit 1
fi

URL="$1"

echo "🔍 Testing YouTube Download"
echo "=========================="
echo ""
echo "URL: $URL"
echo ""

# Step 1: Check available formats
echo "📋 Step 1: Checking available formats..."
echo ""
docker exec yt-dlp-web yt-dlp --list-formats "$URL" | head -30
echo ""

# Step 2: Try downloading with verbose output
echo "⬇️  Step 2: Attempting download..."
echo ""
docker exec yt-dlp-web yt-dlp \
  --verbose \
  --format "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/bestvideo[ext=mp4]+bestaudio/best[ext=mp4]/best" \
  --merge-output-format mp4 \
  --add-metadata \
  --no-part \
  --retries 10 \
  --fragment-retries 10 \
  --output "/downloads/video/TEST-%(title)s.%(ext)s" \
  "$URL" 2>&1 | tee /tmp/yt-dlp-test.log

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Download successful!"
    echo ""
    echo "Files in /downloads/video/:"
    docker exec yt-dlp-web ls -lh /downloads/video/ | grep TEST
else
    echo "❌ Download failed with exit code: $EXIT_CODE"
    echo ""
    echo "Last 20 lines of output:"
    tail -20 /tmp/yt-dlp-test.log
    echo ""
    echo "Full log saved to: /tmp/yt-dlp-test.log"
fi

