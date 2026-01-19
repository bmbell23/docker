#!/bin/bash

# Check ROM collection statistics

GAMES_DIR="/mnt/boston/media/games"

echo "🎮 ROM Collection Statistics"
echo "============================"
echo ""
echo "Location: $GAMES_DIR"
echo ""

total_roms=0

for platform_dir in "$GAMES_DIR"/*; do
    if [ -d "$platform_dir" ]; then
        platform_name=$(basename "$platform_dir")
        
        # Skip backup directories
        if [[ "$platform_name" == "backup" ]] || [[ "$platform_name" == "miyoo backup" ]]; then
            continue
        fi
        
        # Count ROM files
        rom_count=$(find "$platform_dir" -type f \( \
            -iname "*.zip" -o \
            -iname "*.nes" -o \
            -iname "*.sfc" -o \
            -iname "*.smc" -o \
            -iname "*.gb" -o \
            -iname "*.gba" -o \
            -iname "*.gbc" -o \
            -iname "*.md" -o \
            -iname "*.bin" -o \
            -iname "*.iso" -o \
            -iname "*.cue" -o \
            -iname "*.chd" \
        \) 2>/dev/null | wc -l)
        
        if [ "$rom_count" -gt 0 ]; then
            printf "%-20s %5d ROMs\n" "$platform_name:" "$rom_count"
            total_roms=$((total_roms + rom_count))
        fi
    fi
done

echo ""
echo "============================"
printf "%-20s %5d ROMs\n" "TOTAL:" "$total_roms"
echo ""

