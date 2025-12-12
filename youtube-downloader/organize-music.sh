#!/bin/bash
# Helper script to organize YouTube downloads into music library
# This handles files that beets can't auto-match

DOWNLOAD_DIR="/mnt/boston/media/downloads/youtube"
MUSIC_DIR="/mnt/boston/media/music"

echo "🎵 Music Organization Helper"
echo ""
echo "This script will help you organize music that beets couldn't auto-match."
echo ""
echo "Options:"
echo "  1. Try beets auto-import (recommended - will ask for confirmation)"
echo "  2. Manually organize by artist/album"
echo "  3. Move all to 'Non-Album' folder"
echo ""
read -p "Choose option (1-3): " choice

case $choice in
    1)
        echo ""
        echo "Starting beets import..."
        echo "Beets will:"
        echo "  - Try to match each file to MusicBrainz"
        echo "  - Ask you to confirm matches"
        echo "  - Let you manually search if no match found"
        echo ""
        echo "Commands during import:"
        echo "  A = Accept match"
        echo "  S = Skip this file"
        echo "  U = Use as-is (no metadata, just move)"
        echo "  E = Enter metadata manually"
        echo "  I = Search MusicBrainz manually"
        echo ""
        read -p "Press Enter to start..."
        beet import "$DOWNLOAD_DIR"
        ;;
    2)
        echo ""
        read -p "Enter artist name: " artist
        read -p "Enter album name (or press Enter for 'Singles'): " album
        album=${album:-Singles}
        
        mkdir -p "$MUSIC_DIR/$artist/$album"
        
        echo ""
        echo "Moving files to: $MUSIC_DIR/$artist/$album/"
        mv "$DOWNLOAD_DIR"/*.{mp3,opus,m4a} "$MUSIC_DIR/$artist/$album/" 2>/dev/null
        
        echo "✅ Done! Files moved."
        echo "Navidrome will scan within 5 minutes."
        ;;
    3)
        echo ""
        mkdir -p "$MUSIC_DIR/Non-Album"
        echo "Moving all files to: $MUSIC_DIR/Non-Album/"
        mv "$DOWNLOAD_DIR"/*.{mp3,opus,m4a} "$MUSIC_DIR/Non-Album/" 2>/dev/null
        
        echo "✅ Done! Files moved."
        echo "Navidrome will scan within 5 minutes."
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo "📊 Current downloads folder:"
ls -lh "$DOWNLOAD_DIR" | head -20

