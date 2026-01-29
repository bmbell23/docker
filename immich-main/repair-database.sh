#!/bin/bash
# Script to repair Immich database after power outage
# This script will:
# 1. Remove duplicate entries in smart_search table
# 2. Rebuild corrupted indexes
# 3. Run VACUUM ANALYZE to clean up the database

set -e

echo "=== Immich Database Repair Script ==="
echo "Starting database repair process..."
echo ""

# Step 1: Remove duplicates from smart_search table
echo "Step 1: Removing duplicate entries from smart_search table..."
docker exec immich_postgres psql -U postgres -d immich <<'EOF'
-- Delete duplicates, keeping only the first occurrence
DELETE FROM smart_search a USING (
    SELECT MIN(ctid) as ctid, "assetId"
    FROM smart_search 
    GROUP BY "assetId" 
    HAVING COUNT(*) > 1
) b
WHERE a."assetId" = b."assetId" 
AND a.ctid <> b.ctid;
EOF

echo "✓ Duplicates removed"
echo ""

# Step 2: Drop and recreate the corrupted index
echo "Step 2: Rebuilding smart_search_pkey index..."
docker exec immich_postgres psql -U postgres -d immich <<'EOF'
-- Drop the corrupted index
ALTER TABLE smart_search DROP CONSTRAINT IF EXISTS smart_search_pkey CASCADE;

-- Recreate the primary key
ALTER TABLE smart_search ADD PRIMARY KEY ("assetId");
EOF

echo "✓ Primary key rebuilt"
echo ""

# Step 3: Reindex all other indexes
echo "Step 3: Reindexing all database indexes..."
docker exec immich_postgres psql -U postgres -d immich -c "REINDEX DATABASE immich;"

echo "✓ All indexes rebuilt"
echo ""

# Step 4: Run VACUUM ANALYZE
echo "Step 4: Running VACUUM ANALYZE to optimize database..."
docker exec immich_postgres psql -U postgres -d immich -c "VACUUM ANALYZE;"

echo "✓ Database optimized"
echo ""

# Step 5: Check for any remaining corruption
echo "Step 5: Checking for remaining corruption..."
docker exec immich_postgres psql -U postgres -d immich <<'EOF'
-- Check for duplicate entries
SELECT 'Checking for duplicates in smart_search...' as status;
SELECT "assetId", COUNT(*) 
FROM smart_search 
GROUP BY "assetId" 
HAVING COUNT(*) > 1;

-- If no rows returned, duplicates are fixed
SELECT CASE 
    WHEN COUNT(*) = 0 THEN '✓ No duplicates found'
    ELSE '✗ Duplicates still exist!'
END as result
FROM (
    SELECT "assetId", COUNT(*) 
    FROM smart_search 
    GROUP BY "assetId" 
    HAVING COUNT(*) > 1
) sub;
EOF

echo ""
echo "=== Database Repair Complete ==="
echo ""
echo "Next steps:"
echo "1. Review the output above for any errors"
echo "2. Start Immich server: cd immich-main && docker compose start immich-server"
echo "3. Monitor logs: docker logs -f immich_server"
echo "4. Check the web interface to ensure everything works"

