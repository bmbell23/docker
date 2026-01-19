#!/bin/bash

# Rename platform directories to match IGDB slugs
# Based on: https://www.igdb.com/platforms

GAMES_DIR="/mnt/boston/media/games"

echo "🔧 Renaming platform directories to match IGDB slugs"
echo "====================================================="
echo ""
echo "Location: $GAMES_DIR"
echo ""

# Platform mappings: OLD_NAME -> NEW_NAME
declare -A platform_map=(
    ["FC"]="nes"
    ["MD"]="genesis"
    ["SFC"]="snes"
    ["PS"]="ps1"
    ["ms"]="mastersystem"
)

for old_name in "${!platform_map[@]}"; do
    new_name="${platform_map[$old_name]}"
    old_path="$GAMES_DIR/$old_name"
    new_path="$GAMES_DIR/$new_name"
    
    if [ -d "$old_path" ]; then
        echo "📁 Renaming: $old_name → $new_name"
        mv "$old_path" "$new_path"
        echo "   ✅ Done"
    else
        echo "⏭️  Skipping: $old_name (directory not found)"
    fi
done

echo ""
echo "====================================================="
echo "✅ Complete!"
echo ""
echo "Platform directories renamed to match IGDB slugs:"
echo "  FC → nes (Nintendo Entertainment System)"
echo "  MD → genesis (Sega Genesis/Mega Drive)"
echo "  SFC → snes (Super Nintendo)"
echo "  PS → ps1 (PlayStation)"
echo "  ms → mastersystem (Sega Master System)"
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

