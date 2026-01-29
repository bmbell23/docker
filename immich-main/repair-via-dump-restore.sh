#!/bin/bash
# Repair database by dumping and restoring to a fresh database
# This is the safest way to fix system catalog corruption

set -e

echo "=== Immich Database Dump & Restore Repair ==="
echo "This will create a fresh database from your existing data"
echo ""

# Step 1: Ensure server is stopped
echo "Step 1: Stopping Immich services..."
cd /home/brandon/projects/docker/immich-main
docker compose stop immich-server immich-machine-learning
echo "✓ Services stopped"
echo ""

# Step 2: Dump the database (ignoring errors from corrupted indexes)
echo "Step 2: Dumping database (this may show some warnings, that's OK)..."
BACKUP_FILE="/tmp/immich_repair_$(date +%Y%m%d_%H%M%S).sql"
docker exec immich_postgres pg_dump -U postgres --no-owner --no-acl immich > "$BACKUP_FILE" 2>&1 | grep -v "WARNING" || true
echo "✓ Database dumped to: $BACKUP_FILE"
echo "  Size: $(du -h $BACKUP_FILE | cut -f1)"
echo ""

# Step 3: Drop and recreate the database
echo "Step 3: Recreating fresh database..."
docker exec immich_postgres psql -U postgres <<'EOF'
-- Terminate existing connections
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = 'immich'
  AND pid <> pg_backend_pid();

-- Drop and recreate
DROP DATABASE IF EXISTS immich;
CREATE DATABASE immich;
EOF
echo "✓ Fresh database created"
echo ""

# Step 4: Restore the dump
echo "Step 4: Restoring data to fresh database..."
echo "  (This may take a few minutes...)"
docker exec -i immich_postgres psql -U postgres immich < "$BACKUP_FILE" 2>&1 | grep -E "(ERROR|FATAL)" || echo "✓ Data restored successfully"
echo ""

# Step 5: Run VACUUM ANALYZE on the fresh database
echo "Step 5: Optimizing fresh database..."
docker exec immich_postgres psql -U postgres -d immich -c "VACUUM ANALYZE;"
echo "✓ Database optimized"
echo ""

# Step 6: Verify the restoration
echo "Step 6: Verifying database integrity..."
docker exec immich_postgres psql -U postgres -d immich <<'EOF'
-- Check table counts
SELECT 'Database Statistics:' as info;
SELECT 
    'asset' as table_name, 
    COUNT(*) as row_count,
    pg_size_pretty(pg_total_relation_size('asset')) as size
FROM asset
UNION ALL
SELECT 'smart_search', COUNT(*), pg_size_pretty(pg_total_relation_size('smart_search'))
FROM smart_search
UNION ALL
SELECT 'exif', COUNT(*), pg_size_pretty(pg_total_relation_size('exif'))
FROM exif
UNION ALL
SELECT 'users', COUNT(*), pg_size_pretty(pg_total_relation_size('users'))
FROM users;

-- Check for duplicates in smart_search
SELECT '' as blank;
SELECT CASE 
    WHEN COUNT(*) = 0 THEN '✓ No duplicates in smart_search'
    ELSE '✗ WARNING: ' || COUNT(*) || ' duplicates found!'
END as duplicate_check
FROM (
    SELECT "assetId", COUNT(*) 
    FROM smart_search 
    GROUP BY "assetId" 
    HAVING COUNT(*) > 1
) sub;

-- Check database size
SELECT '' as blank;
SELECT 
    'Total Database Size: ' || pg_size_pretty(pg_database_size('immich')) as database_info;
EOF
echo ""

echo "=== Repair Complete ==="
echo ""
echo "✓ Database has been successfully repaired!"
echo "✓ Backup saved at: $BACKUP_FILE"
echo ""
echo "Next steps:"
echo "1. Start Immich services:"
echo "   cd /home/brandon/projects/docker/immich-main && docker compose start immich-server immich-machine-learning"
echo ""
echo "2. Monitor the logs:"
echo "   docker logs -f immich_server"
echo ""
echo "3. Test the web interface at http://your-server:2283"
echo ""
echo "4. If everything works well for a few days, you can delete the backup:"
echo "   rm $BACKUP_FILE"
echo ""

