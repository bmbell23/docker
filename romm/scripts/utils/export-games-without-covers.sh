#!/bin/bash

# Export list of games without cover art to a text file

DB_CONTAINER="romm-db"
DB_USER="romm-user"
DB_PASS="romm-password"
DB_NAME="romm"
OUTPUT_FILE="games-without-covers.txt"

echo "📋 Exporting games without cover art..."

docker exec $DB_CONTAINER mariadb -u$DB_USER -p$DB_PASS $DB_NAME -e "
SELECT 
    p.name as platform,
    r.fs_name as filename,
    r.name as game_name,
    r.id as rom_id
FROM roms r
JOIN platforms p ON r.platform_id = p.id
WHERE 
    (r.path_cover_s IS NULL OR r.path_cover_s = '') AND 
    r.igdb_id IS NULL
ORDER BY p.name, r.fs_name;
" | tail -n +2 > "$OUTPUT_FILE"

count=$(wc -l < "$OUTPUT_FILE")

echo "✅ Exported $count games to $OUTPUT_FILE"
echo ""
echo "You can review this file and decide which games to keep/delete."

