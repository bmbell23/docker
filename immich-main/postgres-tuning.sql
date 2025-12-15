-- PostgreSQL Performance Tuning for Immich
-- Run this after restarting the database to optimize performance

-- Connection and memory settings
ALTER SYSTEM SET max_connections = 50;  -- Reduce from default 100
ALTER SYSTEM SET shared_buffers = '256MB';  -- Reduce to fit in shm_size
ALTER SYSTEM SET effective_cache_size = '2GB';  -- Estimate of OS cache
ALTER SYSTEM SET work_mem = '16MB';  -- Memory for sorts and joins
ALTER SYSTEM SET maintenance_work_mem = '256MB';  -- Memory for maintenance operations

-- Checkpoint and WAL settings for better I/O performance
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET max_wal_size = '2GB';
ALTER SYSTEM SET min_wal_size = '512MB';

-- Query planner settings
ALTER SYSTEM SET random_page_cost = 1.1;  -- Assuming SSD storage
ALTER SYSTEM SET effective_io_concurrency = 200;  -- For SSD

-- Statistics and autovacuum settings
ALTER SYSTEM SET track_activities = on;
ALTER SYSTEM SET track_counts = on;
ALTER SYSTEM SET autovacuum = on;
ALTER SYSTEM SET autovacuum_max_workers = 2;  -- Reduce from default 3
ALTER SYSTEM SET autovacuum_naptime = '1min';

-- Logging for troubleshooting (can be disabled later)
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- Log slow queries (>1s)
ALTER SYSTEM SET log_checkpoints = on;
ALTER SYSTEM SET log_connections = off;  -- Reduce log noise
ALTER SYSTEM SET log_disconnections = off;

-- Apply changes
SELECT pg_reload_conf();

-- Show current settings
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name IN (
    'max_connections', 'shared_buffers', 'effective_cache_size', 
    'work_mem', 'maintenance_work_mem', 'checkpoint_completion_target'
)
ORDER BY name;
