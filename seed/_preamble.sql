-- Included by every seed file (\ir _preamble.sql). Bulk-load session settings.
-- session_replication_role = replica skips FK and user triggers for speed; CHECK, UNIQUE, NOT NULL and EXCLUDE
-- constraints still apply. Everything the skipped triggers/FKs would have guaranteed is proved afterwards by
-- seed/90_validate.sql (generic orphan check over every FK, transition chains, balances, limits).
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET session_replication_role = replica;
SET synchronous_commit = off;
SET maintenance_work_mem = '1GB';
SET work_mem = '256MB';
SET temp_tablespaces = 'talentra_data';
SET client_min_messages = notice;
