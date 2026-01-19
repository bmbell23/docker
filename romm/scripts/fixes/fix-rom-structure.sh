#!/bin/bash

# Fix ROM folder structure for RomM
# RomM expects ROMs to be directly in platform folders, not in 'roms' subdirectories

GAMES_DIR="/mnt/boston/media/games"

echo "🔧 Fixing ROM folder structure for RomM"
echo "========================================"
echo ""
echo "This will move ROMs from platform/roms/ to platform/"
echo "Location: $GAMES_DIR"
echo ""

# Ask for confirmation
read -p "Do you want to continue? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Processing platforms..."
echo ""

# Counter for tracking
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
        
        # Check if there's a 'roms' subdirectory
        roms_subdir="$platform_dir/roms"
        if [ -d "$roms_subdir" ]; then
            # Count files in roms subdirectory
            rom_count=$(find "$roms_subdir" -type f | wc -l)
            
            if [ "$rom_count" -gt 0 ]; then
                echo "📁 Processing: $platform_name ($rom_count files)"
                
                # Move all files from roms/ to parent directory
                mv "$roms_subdir"/* "$platform_dir/" 2>/dev/null
                
                # Remove empty roms directory
                rmdir "$roms_subdir" 2>/dev/null
                
                total_moved=$((total_moved + rom_count))
                platforms_processed=$((platforms_processed + 1))
                
                echo "   ✅ Moved $rom_count files"
            else
                echo "⏭️  Skipping: $platform_name (no files in roms/)"
            fi
        else
            echo "⏭️  Skipping: $platform_name (no roms/ subdirectory)"
        fi
    fi
done

echo ""
echo "========================================"
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

