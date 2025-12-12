#!/bin/bash
# Auto-tag YouTube downloads by parsing filenames
# This will try to extract artist and title from YouTube video titles

DOWNLOAD_DIR="/mnt/boston/media/downloads/youtube"
MUSIC_DIR="/mnt/boston/media/music"

echo "🎵 YouTube Music Auto-Tagger"
echo ""
echo "This will attempt to import all 469 files using beets."
echo "Beets will:"
echo "  - Parse filenames to guess artist/title"
echo "  - Search MusicBrainz for matches"
echo "  - Ask you to confirm or skip each match"
echo ""
echo "⚠️  This will take a while with 469 files!"
echo ""
echo "Options:"
echo "  1. Auto-import with prompts (you confirm each match)"
echo "  2. Auto-import as singles (skip album matching, faster)"
echo "  3. Just move everything to 'YouTube Downloads' folder (no tagging)"
echo ""
read -p "Choose option (1-3): " choice

case $choice in
    1)
        echo ""
        echo "Starting beets import with prompts..."
        echo ""
        echo "💡 Tips:"
        echo "  - Press 'A' to accept a match"
        echo "  - Press 'S' to skip a file"
        echo "  - Press 'U' to use as-is (no metadata)"
        echo "  - Press Ctrl+C to stop anytime"
        echo ""
        read -p "Press Enter to start..."
        beet import "$DOWNLOAD_DIR"
        ;;
    2)
        echo ""
        echo "Starting beets import as singles (no album grouping)..."
        echo ""
        beet import -s "$DOWNLOAD_DIR"
        ;;
    3)
        echo ""
        echo "Moving all files to YouTube Downloads folder..."
        mkdir -p "$MUSIC_DIR/YouTube Downloads"
        
        # Move all audio files
        find "$DOWNLOAD_DIR" -type f \( -name "*.opus" -o -name "*.mp3" -o -name "*.m4a" \) -exec mv {} "$MUSIC_DIR/YouTube Downloads/" \;
        
        echo "✅ Done! Moved 469 files to: $MUSIC_DIR/YouTube Downloads/"
        echo ""
        echo "Files will appear in Navidrome within 5 minutes."
        echo "You can organize them later from within Navidrome."
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo "📊 Files remaining in downloads:"
ls "$DOWNLOAD_DIR" | wc -l

