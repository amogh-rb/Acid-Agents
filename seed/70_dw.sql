-- M19 seed, step 7: load the warehouse marts from the seeded operational data (normal trigger/RI behaviour restored).
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET maintenance_work_mem = '1GB';
SET work_mem = '256MB';
SET temp_tablespaces = 'talentra_data';
SET synchronous_commit = off;

SELECT dw.refresh_marts() AS refresh_result \gset
\echo dw refresh: :refresh_result
SELECT count(*) AS fact_rows FROM dw.fact_application \gset
SELECT count(*) AS dim_candidate_versions FROM dw.dim_candidate \gset
\echo fact_application=:fact_rows dim_candidate=:dim_candidate_versions
