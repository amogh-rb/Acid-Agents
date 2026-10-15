-- Server settings recorded for the performance evidence (docs/02_environment.md). Run: .\run.ps1 settings
SELECT version();
SELECT name, setting, unit, source
  FROM pg_settings
 WHERE name IN ('server_version', 'shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size',
                'max_connections', 'max_wal_size', 'random_page_cost', 'effective_io_concurrency', 'io_method',
                'max_parallel_workers_per_gather', 'jit', 'shared_preload_libraries', 'track_io_timing', 'server_encoding')
 ORDER BY name;
