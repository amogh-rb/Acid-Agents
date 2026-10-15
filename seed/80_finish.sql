-- M19 seed, step 8: identity sequences continue after the loaded ids; statistics and visibility maps for the query work.
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET maintenance_work_mem = '1GB';
SET temp_tablespaces = 'talentra_data';

SELECT seed.sync_sequences() AS sequences_synced;

VACUUM (ANALYZE);
