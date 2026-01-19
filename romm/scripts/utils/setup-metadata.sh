#!/bin/bash

# RomM Metadata Providers Setup Script
# This script helps you configure metadata providers for RomM

set -e

ROMM_DIR="/home/brandon/projects/docker/romm"
cd "$ROMM_DIR"

echo "🎮 RomM Metadata Providers Setup"
echo "=================================="
echo ""

# Check if RomM is running
if ! docker ps | grep -q romm; then
    echo "⚠️  RomM is not running. Starting it now..."
    docker-compose up -d
    echo "✅ RomM started"
    sleep 5
fi

echo "📋 To set up metadata providers, you need API credentials:"
echo ""
echo "1️⃣  IGDB (Required for game metadata)"
echo "   - Go to: https://dev.twitch.tv/console/apps"
echo "   - Register a new application"
echo "   - Get your Client ID and Client Secret"
echo ""
echo "2️⃣  SteamGridDB (Recommended for artwork)"
echo "   - Go to: https://www.steamgriddb.com/profile/preferences/api"
echo "   - Generate an API key"
echo ""
echo "3️⃣  RetroAchievements (Optional for achievements)"
echo "   - Go to: https://retroachievements.org/"
echo "   - Create account and get API key from Settings → Keys"
echo ""

# Ask if user wants to configure IGDB now
read -p "Do you have IGDB credentials to configure now? (y/n): " configure_igdb

if [ "$configure_igdb" = "y" ] || [ "$configure_igdb" = "Y" ]; then
    echo ""
    read -p "Enter IGDB Client ID: " igdb_client_id
    read -p "Enter IGDB Client Secret: " igdb_client_secret

    # Update .env file
    sed -i "s/^IGDB_CLIENT_ID=.*/IGDB_CLIENT_ID=$igdb_client_id/" .env
    sed -i "s/^IGDB_CLIENT_SECRET=.*/IGDB_CLIENT_SECRET=$igdb_client_secret/" .env

    echo "✅ IGDB credentials saved to .env"
    echo "🔄 Restarting RomM to apply changes..."

    # Use kill method (docker restart doesn't work on this server)
    PID=$(docker inspect romm --format '{{.State.Pid}}')
    if [ -n "$PID" ] && [ "$PID" != "0" ]; then
        sudo kill $PID
        echo "   Stopped RomM container..."
        sleep 3
        docker-compose up -d
        echo "✅ RomM restarted"
    else
        echo "⚠️  Could not find RomM PID, trying docker-compose up -d..."
        docker-compose up -d
        echo "✅ RomM started"
    fi
else
    echo ""
    echo "ℹ️  You can add IGDB credentials later by:"
    echo "   1. Edit: $ROMM_DIR/.env"
    echo "   2. Add your IGDB_CLIENT_ID and IGDB_CLIENT_SECRET"
    echo "   3. Restart RomM:"
    echo "      PID=\$(docker inspect romm --format '{{.State.Pid}}')"
    echo "      sudo kill \$PID"
    echo "      sleep 3"
    echo "      cd $ROMM_DIR && docker-compose up -d"
fi

echo ""
echo "📱 Next Steps:"
echo ""
echo "1. Open RomM web UI: http://localhost:8080"
echo ""
echo "2. Configure additional metadata sources:"
echo "   - Go to Settings → Metadata Sources"
echo "   - Add SteamGridDB API key (for artwork)"
echo "   - Add RetroAchievements API key (optional)"
echo ""
echo "3. Scan your library:"
echo "   - Go to Settings → Library"
echo "   - Click 'Scan Library'"
echo "   - Wait for RomM to scan and fetch metadata"
echo ""
echo "4. (Optional) Enable Hasheous for better ROM matching:"
echo "   - Use docker-compose.with-hasheous.yml instead"
echo "   - Run: docker-compose -f docker-compose.with-hasheous.yml up -d"
echo ""

# Check ROM directory structure
echo "📁 Checking ROM directory structure..."
echo ""

GAMES_DIR="/mnt/boston/media/games"
platform_count=0

for platform_dir in "$GAMES_DIR"/*; do
    if [ -d "$platform_dir" ]; then
        platform_name=$(basename "$platform_dir")

        # Skip backup and other non-platform directories
        if [[ "$platform_name" == "backup" ]] || [[ "$platform_name" == "miyoo backup" ]]; then
            continue
        fi

        # Count ROM files
        rom_count=$(find "$platform_dir" -type f \( -iname "*.zip" -o -iname "*.nes" -o -iname "*.sfc" -o -iname "*.gb" -o -iname "*.gba" -o -iname "*.gbc" -o -iname "*.md" -o -iname "*.bin" -o -iname "*.iso" \) 2>/dev/null | wc -l)

        if [ "$rom_count" -gt 0 ]; then
            echo "   ✅ $platform_name: $rom_count ROMs"
            ((platform_count++))
        fi
    fi
done

echo ""
echo "📊 Found $platform_count platforms with ROMs"
echo ""
echo "🎉 Setup complete! Visit http://localhost:8080 to start using RomM"
echo ""
echo "📚 For more information, see: $ROMM_DIR/METADATA_SETUP.md"

