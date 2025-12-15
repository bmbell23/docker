#!/bin/bash

# Script to reorganize ROM folders for RomM compatibility
# RomM expects: /platform/roms/*.rom
# Current structure: /platform/*.rom

GAMES_DIR="/mnt/boston/media/games"

echo "🎮 Reorganizing ROM folders for RomM..."
echo "Games directory: $GAMES_DIR"
echo ""

# List of platform folders to process
PLATFORMS=(
    "arcade"
    "atari2600"
    "atari7800"
    "dos"
    "FC"
    "GB"
    "GBA"
    "GBC"
    "MD"
    "PS"
    "SFC"
    "mame2003"
    "mame2010"
    "ms"
    "neogeo"
)

for platform in "${PLATFORMS[@]}"; do
    platform_dir="$GAMES_DIR/$platform"
    
    # Skip if platform directory doesn't exist
    if [ ! -d "$platform_dir" ]; then
        echo "⏭️  Skipping $platform (directory not found)"
        continue
    fi
    
    # Check if roms/ subdirectory already exists
    if [ -d "$platform_dir/roms" ]; then
        echo "✅ $platform already has roms/ subdirectory"
        continue
    fi
    
    # Count ROM files in the platform directory (not in subdirectories)
    rom_count=$(find "$platform_dir" -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.nes" -o -iname "*.sfc" -o -iname "*.smc" -o -iname "*.gb" -o -iname "*.gbc" -o -iname "*.gba" -o -iname "*.md" -o -iname "*.bin" -o -iname "*.iso" -o -iname "*.cue" -o -iname "*.chd" \) 2>/dev/null | wc -l)
    
    if [ "$rom_count" -eq 0 ]; then
        echo "⏭️  Skipping $platform (no ROM files found)"
        continue
    fi
    
    echo "📦 Processing $platform ($rom_count ROM files)..."
    
    # Create roms/ subdirectory
    mkdir -p "$platform_dir/roms"
    
    # Move all ROM files (and related files like .sav, .srm) into roms/
    find "$platform_dir" -maxdepth 1 -type f \( \
        -iname "*.zip" -o \
        -iname "*.nes" -o \
        -iname "*.sfc" -o \
        -iname "*.smc" -o \
        -iname "*.gb" -o \
        -iname "*.gbc" -o \
        -iname "*.gba" -o \
        -iname "*.md" -o \
        -iname "*.bin" -o \
        -iname "*.iso" -o \
        -iname "*.cue" -o \
        -iname "*.chd" -o \
        -iname "*.sav" -o \
        -iname "*.srm" -o \
        -iname "*.state" \
    \) -exec mv {} "$platform_dir/roms/" \; 2>/dev/null
    
    echo "   ✅ Moved $rom_count files to $platform/roms/"
done

echo ""
echo "🎉 Done! ROM folders reorganized for RomM."
echo ""
echo "Next steps:"
echo "1. Go to RomM web UI (http://localhost:8082)"
echo "2. Settings → Library → Scan Library"
echo "3. Your games should now appear!"

