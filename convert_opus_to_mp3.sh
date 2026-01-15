#!/bin/bash

# Convert a single .opus file to .mp3
# Usage: ./convert_opus_to_mp3.sh /path/to/file.opus

# Check if file argument provided
if [ -z "$1" ]; then
    echo "Usage: $0 <opus-file>"
    echo "Example: $0 /mnt/boston/media/downloads/youtube/song.opus"
    exit 1
fi

OPUS_FILE="$1"

# Check if file exists
if [ ! -f "$OPUS_FILE" ]; then
    echo "Error: File not found: $OPUS_FILE"
    exit 1
fi

# Check if it's actually an opus file
if [[ ! "$OPUS_FILE" =~ \.opus$ ]]; then
    echo "Error: File must have .opus extension"
    echo "Got: $OPUS_FILE"
    exit 1
fi

# Get the output filename (replace .opus with .mp3)
MP3_FILE="${OPUS_FILE%.opus}.mp3"

# Check if mp3 already exists
if [ -f "$MP3_FILE" ]; then
    echo "Warning: MP3 file already exists: $MP3_FILE"
    read -p "Overwrite? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Get the directory containing the file
FILE_DIR="$(dirname "$OPUS_FILE")"
FILE_NAME="$(basename "$OPUS_FILE")"
MP3_NAME="$(basename "$MP3_FILE")"

echo "Converting: $FILE_NAME"
echo "Output: $MP3_NAME"
echo ""

# Use ffmpeg Docker container to convert
docker run --rm \
    -v "$FILE_DIR:/audio" \
    linuxserver/ffmpeg:latest \
    -i "/audio/$FILE_NAME" \
    -vn \
    -ar 44100 \
    -ac 2 \
    -b:a 192k \
    "/audio/$MP3_NAME"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Success! Created: $MP3_FILE"
    echo ""
    read -p "Delete original .opus file? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$OPUS_FILE"
        echo "✓ Deleted: $OPUS_FILE"
    fi
else
    echo ""
    echo "✗ Conversion failed!"
    exit 1
fi

