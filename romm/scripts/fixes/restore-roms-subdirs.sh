#!/bin/bash

# Restore ROMs to roms/ subdirectories for RomM
# It appears RomM's database expects ROMs in platform/roms/ structure

GAMES_DIR="/mnt/boston/media/games"

echo "🔧 Restoring ROM folder structure (moving back to roms/ subdirectories)"
echo "========================================================================"
echo ""
echo "Location: $GAMES_DIR"
echo ""

total_moved=0
platforms_processed=0

# Loop through each platform directory
for platform_dir in "$GAMES_DIR"/*; do
    if [ -d "$platform_dir" ]; then
        platform_name=$(basename "$platform_dir")
        
        # Skip backup directories
        if [[ "$platform_name" == "backup" ]] || [[ "$platform_name" == "miyoo backup" ]]; then
            echo "⏭️  Skipping: $platform_name"
            continue
        fi
        
        # Create roms subdirectory if it doesn't exist
        roms_subdir="$platform_dir/roms"
        mkdir -p "$roms_subdir"
        
        # Count ROM files in platform directory (not in subdirectories)
        rom_count=$(find "$platform_dir" -maxdepth 1 -type f \( \
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
            echo "📁 Processing: $platform_name ($rom_count files)"
            
            # Move ROM files to roms/ subdirectory
            find "$platform_dir" -maxdepth 1 -type f \( \
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
            \) -exec mv {} "$roms_subdir/" \; 2>/dev/null
            
            total_moved=$((total_moved + rom_count))
            platforms_processed=$((platforms_processed + 1))
            
            echo "   ✅ Moved $rom_count files to roms/"
        else
            echo "⏭️  Skipping: $platform_name (no ROM files in root)"
        fi
    fi
done

echo ""
echo "========================================================================"
echo "✅ Complete!"
echo ""
echo "Platforms processed: $platforms_processed"
echo "Total files moved: $total_moved"
echo ""
echo "Next steps:"
echo "1. Restart RomM:"
echo "   PID=\$(docker inspect romm --format '{{.State.Pid}}')"
echo "   sudo kill \$PID"
echo "   sleep 3"
echo "   cd /home/brandon/projects/docker/romm && docker-compose up -d"
echo ""
echo "2. Open RomM: http://localhost:8080"
echo "3. Go to Settings → Library → Scan Library"
echo ""

