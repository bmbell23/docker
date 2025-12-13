#!/bin/bash

# Download YouTube Playlist and Auto-Enhance Metadata
# Usage: ./download-playlist.sh <playlist_url>

set -e

PLAYLIST_URL="$1"

if [ -z "$PLAYLIST_URL" ]; then
    echo "❌ Error: Please provide a playlist URL"
    echo "Usage: $0 <playlist_url>"
    exit 1
fi

echo "🎵 YouTube Playlist Downloader with Auto-Metadata Enhancement"
echo "============================================================"
echo ""
echo "📋 Playlist URL: $PLAYLIST_URL"
echo ""

# Get playlist info
echo "🔍 Fetching playlist info..."
PLAYLIST_INFO=$(docker exec yt-dlp-web yt-dlp --flat-playlist -J "$PLAYLIST_URL" 2>/dev/null || echo "")

if [ -z "$PLAYLIST_INFO" ]; then
    echo "❌ Failed to fetch playlist info. Is the URL correct?"
    exit 1
fi

PLAYLIST_TITLE=$(echo "$PLAYLIST_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('title', 'Unknown Playlist'))" 2>/dev/null || echo "Unknown Playlist")
VIDEO_COUNT=$(echo "$PLAYLIST_INFO" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('entries', [])))" 2>/dev/null || echo "?")

echo "✅ Playlist: $PLAYLIST_TITLE"
echo "✅ Videos: $VIDEO_COUNT"
echo ""

# Ask for confirmation
read -p "📥 Download all $VIDEO_COUNT videos? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Download cancelled"
    exit 0
fi

echo ""
echo "⬇️  Downloading playlist as OPUS audio..."
echo ""

# Download playlist
docker exec yt-dlp-web yt-dlp \
  -f 'bestaudio' \
  --extract-audio \
  --audio-format opus \
  --audio-quality 0 \
  --add-metadata \
  --embed-thumbnail \
  -o '/downloads/%(title)s.%(ext)s' \
  --no-playlist-metafiles \
  --progress \
  "$PLAYLIST_URL"

echo ""
echo "✅ Download complete!"
echo ""

# Ask if user wants to enhance metadata
read -p "🤖 Enhance metadata with MusicBrainz + Ollama? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🤖 Running metadata enhancement..."
    echo ""
    cd /home/brandon/projects/docker/youtube-downloader
    ./enhance-metadata-hybrid.py --only-unknown
else
    echo ""
    echo "ℹ️  You can enhance metadata later by running:"
    echo "   cd /home/brandon/projects/docker/youtube-downloader"
    echo "   ./enhance-metadata-hybrid.py --only-unknown"
fi

echo ""
echo "✅ All done! Files saved to /mnt/boston/media/downloads/youtube"
echo "🎵 Navidrome will pick up changes within 5 minutes!"

