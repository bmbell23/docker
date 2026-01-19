-- Find and delete duplicate ROMs, keeping USA versions over other regions
-- This script identifies duplicates by name and keeps the best version based on region priority

-- Create temporary table to store ROMs we want to keep
CREATE TEMPORARY TABLE IF NOT EXISTS roms_to_keep AS
SELECT 
    r1.id,
    r1.name,
    r1.fs_name,
    -- Priority: USA=1, World=2, Europe=3, Japan=4, Other=5
    CASE 
        WHEN r1.fs_name REGEXP '\\(USA?\\)|\\(U\\)' THEN 1
        WHEN r1.fs_name REGEXP '\\(World\\)|\\(USA?, Europe\\)' THEN 2
        WHEN r1.fs_name REGEXP '\\(Europe?\\)|\\(EU\\)' THEN 3
        WHEN r1.fs_name REGEXP '\\(Japan\\)|\\(J\\)' THEN 4
        ELSE 5
    END as region_priority,
    -- Penalize beta/proto versions
    CASE 
        WHEN r1.fs_name REGEXP '\\(Beta\\)|\\(Proto\\)|\\(Demo\\)|\\(Sample\\)' THEN 1
        ELSE 0
    END as is_beta
FROM roms r1
WHERE r1.name IS NOT NULL AND r1.name != '';

-- Show duplicates we're about to delete
SELECT 
    r.id,
    r.name,
    r.fs_name,
    'WILL DELETE' as action,
    CONCAT('Keeping ID ', k.id, ': ', k.fs_name) as reason
FROM roms r
INNER JOIN (
    SELECT name, MIN(id) as keep_id
    FROM (
        SELECT id, name, region_priority, is_beta
        FROM roms_to_keep
        ORDER BY name, region_priority, is_beta, id
    ) ranked
    GROUP BY name
    HAVING COUNT(*) > 1
) duplicates ON r.name = duplicates.name
INNER JOIN roms_to_keep k ON k.id = duplicates.keep_id
WHERE r.id != duplicates.keep_id
ORDER BY r.name, r.id;

-- Delete the duplicates (keeping the one with best region priority and lowest ID)
DELETE r FROM roms r
WHERE r.id IN (
    SELECT id FROM (
        SELECT r2.id
        FROM roms r2
        INNER JOIN (
            SELECT name, MIN(id) as keep_id
            FROM (
                SELECT id, name, region_priority, is_beta
                FROM roms_to_keep
                ORDER BY name, region_priority, is_beta, id
            ) ranked
            GROUP BY name
            HAVING COUNT(*) > 1
        ) duplicates ON r2.name = duplicates.name
        WHERE r2.id != duplicates.keep_id
    ) to_delete
);

-- Show summary
SELECT 
    'Cleanup complete' as status,
    COUNT(*) as remaining_roms
FROM roms;

DROP TEMPORARY TABLE IF EXISTS roms_to_keep;

