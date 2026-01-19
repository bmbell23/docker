#!/bin/bash

# Fix platform names and IGDB IDs in RomM database
# This script updates platform display names and links them to IGDB for metadata

set -e

echo "Fixing platform names and IGDB IDs in RomM database..."

# Database connection details
DB_CONTAINER="romm-db"
DB_USER="root"
DB_PASS="romm-root-password"
DB_NAME="romm"

# Function to update platform custom name and IGDB ID
update_platform() {
    local slug="$1"
    local custom_name="$2"
    local igdb_id="$3"

    echo "Updating platform '$slug' to '$custom_name' (IGDB ID: $igdb_id)..."
    docker exec "$DB_CONTAINER" mariadb -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -e "UPDATE platforms SET custom_name = '$custom_name', igdb_id = $igdb_id WHERE slug = '$slug';"
}

# Update platform names and IGDB IDs
# Format: update_platform "slug" "Custom Name" igdb_id
update_platform "ps1" "PlayStation" 7
update_platform "easyrpg" "EasyRPG" "NULL"
update_platform "mame2003" "MAME 2003" "NULL"
update_platform "mame2010" "MAME 2010" "NULL"
update_platform "mastersystem" "Sega Master System" 64
update_platform "neogeo" "Neo Geo" 80

echo ""
echo "Platform names and IGDB IDs updated successfully!"
echo ""
echo "Updated platforms:"
docker exec "$DB_CONTAINER" mariadb -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    -e "SELECT slug, name, custom_name, igdb_id FROM platforms WHERE slug IN ('ps1', 'easyrpg', 'mame2003', 'mame2010', 'mastersystem', 'neogeo') ORDER BY slug;"

echo ""
echo "Done! Restart the RomM container to see the changes."

