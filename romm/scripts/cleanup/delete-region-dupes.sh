#!/bin/bash
# Delete duplicate ROMs, keeping USA versions

echo "🔍 Finding and deleting region duplicates..."
echo ""

docker exec romm-db mariadb -uromm-user -promm-password romm -e "
-- Delete Europe/other region versions when USA version exists
DELETE r1 FROM roms r1
INNER JOIN roms r2 ON r1.name = r2.name AND r1.id != r2.id
WHERE r1.name IS NOT NULL 
AND r1.name != ''
-- r1 is NOT a USA version
AND r1.fs_name NOT REGEXP '\\(USA?\\)'
AND r1.fs_name NOT REGEXP '\\(U\\)'
-- r2 IS a USA version
AND (r2.fs_name REGEXP '\\(USA?\\)' OR r2.fs_name REGEXP '\\(U\\)')
-- Keep the USA version (r2)
AND r1.id > r2.id;

SELECT ROW_COUNT() as deleted_count;
"

echo ""
echo "✅ Deleted non-USA duplicates where USA version exists"
echo ""
echo "Remaining duplicates (if any):"

docker exec romm-db mariadb -uromm-user -promm-password romm -e "
SELECT 
    name,
    COUNT(*) as count,
    GROUP_CONCAT(SUBSTRING(fs_name, 1, 60) ORDER BY id SEPARATOR ' | ') as versions
FROM roms
WHERE name IS NOT NULL AND name != ''
GROUP BY name
HAVING COUNT(*) > 1
ORDER BY count DESC, name
LIMIT 20;
"

