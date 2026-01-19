#!/bin/bash
# Cleanup duplicate ROMs, keeping USA versions over other regions

echo "🔍 Finding duplicate ROMs (keeping USA versions)..."

docker exec romm-db mariadb -uromm-user -promm-password romm <<'EOF'

-- Find duplicates by name and delete non-USA versions
SET @deleted = 0;

-- Create a list of ROMs to delete (duplicates where a USA version exists)
CREATE TEMPORARY TABLE roms_to_delete AS
SELECT r1.id, r1.name, r1.fs_name
FROM roms r1
WHERE EXISTS (
    -- Check if there's another ROM with the same name
    SELECT 1 FROM roms r2
    WHERE r2.name = r1.name
    AND r2.id != r1.id
    AND r2.name IS NOT NULL
    AND r2.name != ''
)
AND r1.name IS NOT NULL
AND r1.name != ''
-- Delete this one if it's NOT a USA version, OR if there's a better USA version with lower ID
AND (
    -- Not a USA version
    (r1.fs_name NOT REGEXP '\\(USA?\\)' AND r1.fs_name NOT REGEXP '\\(U\\)')
    OR
    -- Is USA but there's another USA with lower ID
    EXISTS (
        SELECT 1 FROM roms r3
        WHERE r3.name = r1.name
        AND r3.id < r1.id
        AND (r3.fs_name REGEXP '\\(USA?\\)' OR r3.fs_name REGEXP '\\(U\\)')
    )
)
-- But keep it if it's the ONLY USA version
AND NOT (
    (r1.fs_name REGEXP '\\(USA?\\)' OR r1.fs_name REGEXP '\\(U\\)')
    AND NOT EXISTS (
        SELECT 1 FROM roms r4
        WHERE r4.name = r1.name
        AND r4.id != r1.id
        AND (r4.fs_name REGEXP '\\(USA?\\)' OR r4.fs_name REGEXP '\\(U\\)')
    )
);

-- Show what we're deleting
SELECT 
    CONCAT('   🗑️  Deleting: ', name, ' - ', fs_name, ' (ID: ', id, ')') as action
FROM roms_to_delete
ORDER BY name, id;

-- Count how many we're deleting
SELECT COUNT(*) INTO @deleted FROM roms_to_delete;

-- Delete them
DELETE FROM roms WHERE id IN (SELECT id FROM roms_to_delete);

-- Show summary
SELECT 
    CONCAT('✅ Deleted ', @deleted, ' duplicate ROMs (kept USA versions)') as summary;

-- Show remaining duplicates
SELECT 
    name,
    COUNT(*) as count,
    GROUP_CONCAT(fs_name ORDER BY id SEPARATOR ' | ') as versions
FROM roms
WHERE name IS NOT NULL AND name != ''
GROUP BY name
HAVING COUNT(*) > 1
ORDER BY count DESC
LIMIT 10;

DROP TEMPORARY TABLE roms_to_delete;

EOF

echo ""
echo "✅ Cleanup complete!"

