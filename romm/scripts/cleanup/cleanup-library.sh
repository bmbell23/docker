#!/bin/bash

# Comprehensive ROM library cleanup script
# Handles: duplicates, non-English games, games without covers, number prefixes

GAMES_DIR="/mnt/boston/media/games"
DB_CONTAINER="romm-db"
DB_USER="romm-user"
DB_PASS="romm-password"
DB_NAME="romm"

echo "🧹 ROM Library Cleanup"
echo "====================="
echo ""

# Function to execute SQL
run_sql() {
    docker exec $DB_CONTAINER mariadb -u$DB_USER -p$DB_PASS $DB_NAME -e "$1"
}

# 1. DELETE NON-ENGLISH GAMES
echo "1️⃣  Deleting non-English games..."
echo ""

# Get list of non-English ROMs
NON_ENGLISH=$(run_sql "SELECT id, fs_name, fs_path FROM roms WHERE
    fs_name LIKE '%(Japan%' OR
    fs_name LIKE '%(Germany%' OR
    fs_name LIKE '%(France%' OR
    fs_name LIKE '%(Spain%' OR
    fs_name LIKE '%(Italy%' OR
    fs_name LIKE '%(J)%' OR
    fs_name LIKE '%(G)%' OR
    fs_name LIKE '%(F)%' OR
    fs_name LIKE '%Translated%' OR
    fs_name LIKE '%(Unl)%';" | tail -n +2)

deleted_non_english=0
while IFS=$'\t' read -r id fs_name fs_path; do
    if [ -n "$id" ]; then
        # Delete the file
        full_path="/romm/library/$fs_path"
        docker exec romm rm -f "$full_path" 2>/dev/null

        # Delete from database
        run_sql "DELETE FROM roms WHERE id=$id;" >/dev/null 2>&1

        deleted_non_english=$((deleted_non_english + 1))
        echo "   🗑️  $fs_name"
    fi
done <<< "$NON_ENGLISH"

echo "   Deleted $deleted_non_english non-English games"
echo ""

# 2. REPORT GAMES WITHOUT COVER ART (don't delete yet)
echo "2️⃣  Checking games without cover art..."
echo ""

no_cover_count=$(run_sql "SELECT COUNT(*) FROM roms WHERE
    (path_cover_s IS NULL OR path_cover_s = '') AND
    igdb_id IS NULL;" | tail -n +2)

echo "   Found $no_cover_count games without covers or IGDB metadata"
echo "   ⚠️  Run a FULL RESCAN first to try to get metadata for these games"
echo "   ⚠️  After rescan, we can delete games that still have no metadata"
echo ""

deleted_no_covers=0

# 3. REMOVE DUPLICATES (keep the one with lowest ID)
echo "3️⃣  Removing duplicate games..."
echo ""

# Get duplicates
DUPLICATES=$(run_sql "SELECT name, GROUP_CONCAT(id ORDER BY id) as ids
    FROM roms
    WHERE name IS NOT NULL AND name != ''
    GROUP BY name
    HAVING COUNT(*) > 1;" | tail -n +2)

deleted_duplicates=0
while IFS=$'\t' read -r name ids; do
    if [ -n "$ids" ]; then
        # Split IDs and keep first one
        IFS=',' read -ra ID_ARRAY <<< "$ids"
        keep_id="${ID_ARRAY[0]}"

        # Delete all others
        for id in "${ID_ARRAY[@]:1}"; do
            # Get file path
            fs_path=$(run_sql "SELECT fs_path FROM roms WHERE id=$id;" | tail -n +2)

            if [ -n "$fs_path" ]; then
                # Delete the file
                full_path="/romm/library/$fs_path"
                docker exec romm rm -f "$full_path" 2>/dev/null

                # Delete from database
                run_sql "DELETE FROM roms WHERE id=$id;" >/dev/null 2>&1

                deleted_duplicates=$((deleted_duplicates + 1))
                echo "   🗑️  Duplicate: $name (ID: $id, keeping ID: $keep_id)"
            fi
        done
    fi
done <<< "$DUPLICATES"

echo "   Deleted $deleted_duplicates duplicate games"
echo ""

# 4. FIX NUMBER PREFIXES (this should be rare after rescan)
echo "4️⃣  Checking for number prefixes..."
echo ""

count=$(run_sql "SELECT COUNT(*) FROM roms WHERE fs_name REGEXP '^[0-9]+ - ';" | tail -n +2)
echo "   Found $count games with number prefixes"
echo "   (These should be fixed by running the full rescan in ROMM)"
echo ""

echo "✅ Cleanup complete!"
echo ""
echo "Summary:"
echo "  - Deleted $deleted_non_english non-English games"
echo "  - Deleted $deleted_no_covers games without covers"
echo "  - Deleted $deleted_duplicates duplicate games"
echo ""
echo "⚠️  IMPORTANT: Run a FULL RESCAN in ROMM to update the database!"

