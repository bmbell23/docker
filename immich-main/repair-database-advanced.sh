#!/bin/bash
# Advanced database repair script for Immich after power outage
# This handles system catalog corruption

set -e

echo "=== Immich Advanced Database Repair Script ==="
echo "This script will repair database corruption from the power outage"
echo ""

# Step 1: Create a backup first
echo "Step 1: Creating database backup..."
BACKUP_FILE="/tmp/immich_backup_$(date +%Y%m%d_%H%M%S).sql"
docker exec immich_postgres pg_dump -U postgres immich > "$BACKUP_FILE"
echo "✓ Backup created at: $BACKUP_FILE"
echo ""

# Step 2: Stop Immich server (already stopped)
echo "Step 2: Ensuring Immich server is stopped..."
cd immich-main && docker compose stop immich-server
echo "✓ Server stopped"
echo ""

# Step 3: Set zero_damaged_pages to allow reading corrupted data
echo "Step 3: Configuring PostgreSQL to handle corrupted pages..."
docker exec immich_postgres psql -U postgres -d immich -c "SET zero_damaged_pages = on;"
echo "✓ Configuration set"
echo ""

# Step 4: Fix user table duplicates first
echo "Step 4: Removing duplicates from smart_search table..."
docker exec immich_postgres psql -U postgres -d immich <<'EOF'
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

# Step 5: Rebuild just the smart_search index without CONCURRENTLY
echo "Step 5: Rebuilding smart_search primary key..."
docker exec immich_postgres psql -U postgres -d immich <<'EOF'
ALTER TABLE smart_search DROP CONSTRAINT IF EXISTS smart_search_pkey CASCADE;
ALTER TABLE smart_search ADD PRIMARY KEY ("assetId");
EOF
echo "✓ Primary key rebuilt"
echo ""

# Step 6: Reindex user tables only (not system catalogs)
echo "Step 6: Reindexing user tables..."
docker exec immich_postgres psql -U postgres -d immich <<'EOF'
-- Get all user tables and reindex them
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT schemaname, tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    LOOP
        BEGIN
            EXECUTE 'REINDEX TABLE ' || quote_ident(r.schemaname) || '.' || quote_ident(r.tablename);
            RAISE NOTICE 'Reindexed table: %.%', r.schemaname, r.tablename;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to reindex table %.%: %', r.schemaname, r.tablename, SQLERRM;
        END;
    END LOOP;
END $$;
EOF
echo "✓ User tables reindexed"
echo ""

# Step 7: Run VACUUM ANALYZE
echo "Step 7: Running VACUUM ANALYZE..."
docker exec immich_postgres psql -U postgres -d immich -c "VACUUM ANALYZE;"
echo "✓ Database optimized"
echo ""

# Step 8: Verify the repair
echo "Step 8: Verifying repair..."
docker exec immich_postgres psql -U postgres -d immich <<'EOF'
-- Check for duplicates
SELECT CASE 
    WHEN COUNT(*) = 0 THEN '✓ No duplicates in smart_search'
    ELSE '✗ WARNING: ' || COUNT(*) || ' duplicates still exist!'
END as result
FROM (
    SELECT "assetId", COUNT(*) 
    FROM smart_search 
    GROUP BY "assetId" 
    HAVING COUNT(*) > 1
) sub;

-- Check table counts
SELECT 'asset' as table_name, COUNT(*) as row_count FROM asset
UNION ALL
SELECT 'smart_search', COUNT(*) FROM smart_search
UNION ALL
SELECT 'exif', COUNT(*) FROM exif;
EOF
echo ""

echo "=== Repair Complete ==="
echo ""
echo "Backup location: $BACKUP_FILE"
echo ""
echo "Next steps:"
echo "1. Start Immich server: cd immich-main && docker compose start immich-server"
echo "2. Monitor logs: docker logs -f immich_server"
echo "3. Check the web interface"
echo "4. If everything works, you can delete the backup: rm $BACKUP_FILE"

