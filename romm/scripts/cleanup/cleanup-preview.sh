#!/bin/bash

# Preview what the cleanup script will do without actually deleting anything

DB_CONTAINER="romm-db"
DB_USER="romm-user"
DB_PASS="romm-password"
DB_NAME="romm"

echo "🔍 ROMM Cleanup Preview (Dry Run)"
echo "=" | tr '=' '=' | head -c 50; echo ""
echo ""

# Function to execute SQL
run_sql() {
    docker exec $DB_CONTAINER mariadb -u$DB_USER -p$DB_PASS $DB_NAME -e "$1"
}

# Get total count
total=$(run_sql "SELECT COUNT(*) FROM roms;" | tail -n +2)
echo "📊 Total games in library: $total"
echo ""

# 1. Check (USA, Europe) duplicates
echo "1️⃣  (USA, Europe) duplicates that could be removed:"
usa_europe=$(run_sql "SELECT COUNT(*) FROM roms WHERE fs_name LIKE '%(USA, Europe)%';" | tail -n +2)
echo "   Found: $usa_europe games"
echo "   Sample:"
run_sql "SELECT fs_name FROM roms WHERE fs_name LIKE '%(USA, Europe)%' LIMIT 5;" | tail -n +2 | while read -r name; do
    echo "      - $name"
done
echo ""

# 2. Check regional duplicates
echo "2️⃣  Regional duplicates (same game, different regions):"
echo "   Checking for games with both USA and Europe versions..."
duplicates=$(run_sql "
    SELECT COUNT(DISTINCT r1.name) 
    FROM roms r1 
    JOIN roms r2 ON r1.name = r2.name AND r1.id != r2.id
    WHERE r1.fs_name LIKE '%(USA)%' 
    AND r2.fs_name LIKE '%(Europe)%'
" | tail -n +2)
echo "   Found: ~$duplicates games with multiple regional versions"
echo "   Sample:"
run_sql "
    SELECT r1.fs_name as usa_version, r2.fs_name as europe_version
    FROM roms r1 
    JOIN roms r2 ON r1.name = r2.name AND r1.id != r2.id
    WHERE r1.fs_name LIKE '%(USA)%' 
    AND r2.fs_name LIKE '%(Europe)%'
    LIMIT 5
" | tail -n +2 | while read -r line; do
    echo "      $line"
done
echo ""

# 3. Check non-playable files
echo "3️⃣  Non-playable files (Disc 2+, BIOS, etc.):"
disc2=$(run_sql "SELECT COUNT(*) FROM roms WHERE fs_name REGEXP '\\(Disc [2-9]\\)';" | tail -n +2)
bios=$(run_sql "SELECT COUNT(*) FROM roms WHERE fs_name LIKE '%BIOS%' OR fs_name LIKE '%[BIOS]%';" | tail -n +2)
echo "   Multi-disc (Disc 2+): $disc2"
echo "   BIOS files: $bios"
if [ "$disc2" -gt 0 ]; then
    echo "   Sample multi-disc:"
    run_sql "SELECT fs_name FROM roms WHERE fs_name REGEXP '\\(Disc [2-9]\\)' LIMIT 3;" | tail -n +2 | while read -r name; do
        echo "      - $name"
    done
fi
echo ""

# 4. Check for special characters
echo "4️⃣  Games with special characters (may prevent metadata):"
special=$(run_sql "SELECT COUNT(*) FROM roms WHERE fs_name REGEXP '[^a-zA-Z0-9 ._(),&-]';" | tail -n +2)
echo "   Found: $special games"
echo "   Sample:"
run_sql "SELECT fs_name FROM roms WHERE fs_name REGEXP '[^a-zA-Z0-9 ._(),&-]' LIMIT 5;" | tail -n +2 | while read -r name; do
    echo "      - $name"
done
echo ""

# 5. Check games without metadata
echo "5️⃣  Games without metadata:"
no_metadata=$(run_sql "SELECT COUNT(*) FROM roms WHERE igdb_id IS NULL;" | tail -n +2)
echo "   Found: $no_metadata games without IGDB metadata"
echo "   Sample:"
run_sql "SELECT fs_name FROM roms WHERE igdb_id IS NULL LIMIT 5;" | tail -n +2 | while read -r name; do
    echo "      - $name"
done
echo ""

# 6. Check undesirable versions
echo "6️⃣  Undesirable versions (Beta, Proto, Demo, Hacks):"
beta=$(run_sql "SELECT COUNT(*) FROM roms WHERE fs_name REGEXP '\\((Beta|Proto|Demo|Sample|Unl|Pirate|Hack|Bad)\\)';" | tail -n +2)
echo "   Found: $beta games"
if [ "$beta" -gt 0 ]; then
    echo "   Sample:"
    run_sql "SELECT fs_name FROM roms WHERE fs_name REGEXP '\\((Beta|Proto|Demo|Sample|Unl|Pirate|Hack|Bad)\\)' LIMIT 5;" | tail -n +2 | while read -r name; do
        echo "      - $name"
    done
fi
echo ""

# Summary
echo "=" | tr '=' '=' | head -c 50; echo ""
echo "📋 Summary of potential cleanup:"
echo ""
estimated_deletions=$((usa_europe + duplicates + disc2 + bios + beta))
echo "   Estimated games to be removed: ~$estimated_deletions"
echo "   Games remaining: ~$((total - estimated_deletions))"
echo ""
echo "⚠️  This is just a preview. No changes have been made."
echo ""
echo "To run the actual cleanup:"
echo "   cd /home/brandon/projects/docker/romm"
echo "   python3 comprehensive-cleanup.py"

