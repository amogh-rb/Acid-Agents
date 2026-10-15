-- M1 (B1): extensions, module schemas and group roles.
-- run.ps1 creates the database itself (UTF8, ICU 'und' collation); this file runs inside it.

CREATE EXTENSION IF NOT EXISTS btree_gist;  -- EXCLUDE constraints that mix = and && (non-overlap rules RG10, B34, B35)
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- fuzzy multilingual name / title search and candidate de-duplication
CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- digest() for lookup hashes, pgp_sym_encrypt() for Sensitive columns

-- pg_stat_statements only works when preloaded; create it when the server allows (see docs/04_environment.md).
DO $$
BEGIN
  IF current_setting('shared_preload_libraries') ~ 'pg_stat_statements' THEN
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
  END IF;
END $$;

-- One schema per module. Schemas are namespaces, not name prefixes (RG1).
CREATE SCHEMA ref;     COMMENT ON SCHEMA ref     IS 'Master data: geography, skills, qualifications, every enumeration lookup, UI labels and translations';
CREATE SCHEMA admin;   COMMENT ON SCHEMA admin   IS 'Administration: users, credentials, roles, permissions, consent, blocking';
CREATE SCHEMA org;     COMMENT ON SCHEMA org     IS 'Organisation and account: employers, clients, locations, identifiers, verification, recruiter mapping';
CREATE SCHEMA profile; COMMENT ON SCHEMA profile IS 'Candidate profile: identity, contact, education, experience, skills, resumes, assessments, view and activity history';
CREATE SCHEMA job;     COMMENT ON SCHEMA job     IS 'Jobs and applications: requirements, positions, questionnaires, applications, pipeline, shortlists, interviews, offers';
CREATE SCHEMA gig;     COMMENT ON SCHEMA gig     IS 'Gig marketplace: gig requests, gig workers, applications, assignments, fulfilment handoff, earnings, ratings';
CREATE SCHEMA lic;     COMMENT ON SCHEMA lic     IS 'Licences, seats, devices and sessions';
CREATE SCHEMA src;     COMMENT ON SCHEMA src     IS 'Sourcing and consultant requests, outreach batches and recipients';
CREATE SCHEMA billing; COMMENT ON SCHEMA billing IS 'Plans, subscriptions, payments, invoices, refunds, wallet ledger, credit consumption, profile downloads';
CREATE SCHEMA notif;   COMMENT ON SCHEMA notif   IS 'Notifications, preferences, community, support tickets, FAQs';
CREATE SCHEMA dw;      COMMENT ON SCHEMA dw      IS 'Analytics layer: dim_, fact_, agg_ objects (derived, never written by the application)';
CREATE SCHEMA audit;   COMMENT ON SCHEMA audit   IS 'Append-only audit trail, error log and the append-only guard functions';
CREATE SCHEMA app;     COMMENT ON SCHEMA app     IS 'Database API functions that enforce multi-row rules (session start/end, ledger posting)';

-- Group roles (cluster-wide, so created only if missing). Login roles are granted these later (M18).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'talentra_app') THEN
    CREATE ROLE talentra_app NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'talentra_readonly') THEN
    CREATE ROLE talentra_readonly NOLOGIN;
  END IF;
  -- writes integration-boundary tables (gig earnings, provider callbacks); the application role only reads them
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'talentra_integration') THEN
    CREATE ROLE talentra_integration NOLOGIN;
  END IF;
END $$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
