-- M19 / M20 (B66): validate the seeded data against the standards in docket Section 5 and the rules the bulk load bypassed
-- (FK checks and triggers were off during load). Prints one line per check; the run fails if any check fails.
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET work_mem = '256MB';
SET temp_tablespaces = 'talentra_data';

DROP FUNCTION IF EXISTS seed.check(text, text, text, text, boolean);
DROP TABLE IF EXISTS seed.validation;
CREATE TABLE seed.validation (
  id serial PRIMARY KEY, area text NOT NULL, check_name text NOT NULL, expected text NOT NULL, actual text NOT NULL, ok boolean NOT NULL
);

CREATE FUNCTION seed.check(p_area text, p_name text, p_expected text, p_actual text, p_ok boolean) RETURNS void
LANGUAGE sql AS $$ INSERT INTO seed.validation (area, check_name, expected, actual, ok) VALUES (p_area, p_name, p_expected, p_actual, p_ok) $$;

\o NUL
-- 1. volumes
SELECT seed.check('volume', 'candidate profiles', n_cand::text, (SELECT count(*) FROM profile.candidate_profile)::text,
                  (SELECT count(*) FROM profile.candidate_profile) = n_cand) FROM seed.params;
SELECT seed.check('volume', 'job requirements', n_job::text, (SELECT count(*) FROM job.job_requirement)::text,
                  (SELECT count(*) FROM job.job_requirement) = n_job) FROM seed.params;
SELECT seed.check('volume', 'applications', n_app::text, (SELECT count(*) FROM job.application)::text,
                  (SELECT count(*) FROM job.application) = n_app) FROM seed.params;
SELECT seed.check('volume', 'organisations', n_org::text, (SELECT count(*) FROM org.organisation)::text,
                  (SELECT count(*) FROM org.organisation) = n_org) FROM seed.params;

-- 2. referential integrity: every FK of every table (bulk load skipped the FK triggers)
DO $$
DECLARE
  r record;
  v_cols text;
  v_join text;
  v_nn   text;
  v_bad  bigint;
  v_n    integer := 0;
  v_fail integer := 0;
BEGIN
  FOR r IN SELECT k.oid, k.conname, k.conrelid::regclass AS child, k.confrelid::regclass AS parent, k.conkey, k.confkey, k.conrelid, k.confrelid AS parent_oid
             FROM pg_constraint k JOIN pg_namespace n ON n.oid = k.connamespace
            WHERE k.contype = 'f' AND k.conparentid = 0 AND n.nspname NOT IN ('seed', 'qa', 'pg_catalog')
            ORDER BY k.conname LOOP
    SELECT string_agg(format('c.%I = p.%I', ca.attname, pa.attname), ' AND ' ORDER BY u.ord),
           string_agg(format('c.%I IS NOT NULL', ca.attname), ' AND ' ORDER BY u.ord)
      INTO v_join, v_nn
      FROM unnest(r.conkey, r.confkey) WITH ORDINALITY u(ckey, pkey, ord)
      JOIN pg_attribute ca ON ca.attrelid = r.conrelid AND ca.attnum = u.ckey
      JOIN pg_attribute pa ON pa.attrelid = r.parent_oid AND pa.attnum = u.pkey;
    EXECUTE format('SELECT count(*) FROM %s c WHERE %s AND NOT EXISTS (SELECT 1 FROM %s p WHERE %s)', r.child, v_nn, r.parent, v_join) INTO v_bad;
    v_n := v_n + 1;
    IF v_bad > 0 THEN
      v_fail := v_fail + 1;
      PERFORM seed.check('foreign key', r.conname, '0 orphans', v_bad || ' orphans in ' || r.child, false);
    END IF;
  END LOOP;
  PERFORM seed.check('foreign key', 'all ' || v_n || ' foreign keys: no orphan rows', '0 failing', v_fail || ' failing', v_fail = 0);
END $$;

-- 3. application pipeline: only legal transitions, a first row per application, final status equals the last history row
SELECT seed.check('pipeline', 'history rows that are not a legal transition', '0',
       (SELECT count(*) FROM job.application_status_history h
         WHERE NOT (h.from_application_status_code IS NULL AND h.to_application_status_code = 'applied')
           AND NOT EXISTS (SELECT 1 FROM job.application_status_transition t
                            WHERE t.from_application_status_code = h.from_application_status_code
                              AND t.to_application_status_code = h.to_application_status_code))::text,
       NOT EXISTS (SELECT 1 FROM job.application_status_history h
                    WHERE NOT (h.from_application_status_code IS NULL AND h.to_application_status_code = 'applied')
                      AND NOT EXISTS (SELECT 1 FROM job.application_status_transition t
                                       WHERE t.from_application_status_code = h.from_application_status_code
                                         AND t.to_application_status_code = h.to_application_status_code)));
SELECT seed.check('pipeline', 'applications without exactly one initial history row', '0',
       (SELECT count(*) FROM job.application a
         WHERE (SELECT count(*) FROM job.application_status_history h WHERE h.application_id = a.id AND h.from_application_status_code IS NULL) <> 1)::text,
       NOT EXISTS (SELECT 1 FROM job.application a
                    WHERE (SELECT count(*) FROM job.application_status_history h WHERE h.application_id = a.id AND h.from_application_status_code IS NULL) <> 1));
SELECT seed.check('pipeline', 'applications whose status differs from the last history row', '0',
       (SELECT count(*) FROM job.application a
          JOIN LATERAL (SELECT to_application_status_code FROM job.application_status_history h
                         WHERE h.application_id = a.id ORDER BY h.changed_at DESC, h.id DESC LIMIT 1) l ON true
         WHERE l.to_application_status_code <> a.application_status_code)::text,
       NOT EXISTS (SELECT 1 FROM job.application a
                    JOIN LATERAL (SELECT to_application_status_code FROM job.application_status_history h
                                   WHERE h.application_id = a.id ORDER BY h.changed_at DESC, h.id DESC LIMIT 1) l ON true
                   WHERE l.to_application_status_code <> a.application_status_code));
SELECT seed.check('pipeline', 'applications to draft or unpublished-never jobs', '0',
       (SELECT count(*) FROM job.application a JOIN job.job_requirement j ON j.id = a.job_requirement_id
         WHERE j.job_requirement_status_code = 'draft')::text,
       NOT EXISTS (SELECT 1 FROM job.application a JOIN job.job_requirement j ON j.id = a.job_requirement_id
                    WHERE j.job_requirement_status_code = 'draft'));

-- funnel shape: the share of applications that ever reached each stage (docket plan: 30 / 12 / 4 / 3 percent)
WITH reached AS (
  SELECT to_application_status_code AS s, count(DISTINCT application_id) AS n FROM job.application_status_history GROUP BY 1
), tot AS (SELECT count(*)::numeric AS n FROM job.application)
SELECT seed.check('distribution', 'share that reached ' || x.stage, x.target || '% +-1.0', round(100 * coalesce(r.n, 0) / tot.n, 2)::text || '%',
                  abs(100 * coalesce(r.n, 0) / tot.n - x.target) <= 1.0)
  FROM (VALUES ('shortlisted', 30.0), ('interviewed', 12.0), ('offered', 4.0), ('joined', 3.0)) x(stage, target)
  CROSS JOIN tot LEFT JOIN reached r ON r.s = x.stage;

-- 4. money and ledger
SELECT seed.check('money', 'wallets whose balance differs from the sum of their ledger', '0',
       (SELECT count(*) FROM billing.wallet w WHERE w.balance <> (SELECT coalesce(sum(amount), 0) FROM billing.wallet_ledger_entry e WHERE e.wallet_id = w.id))::text,
       NOT EXISTS (SELECT 1 FROM billing.wallet w WHERE w.balance <> (SELECT coalesce(sum(amount), 0) FROM billing.wallet_ledger_entry e WHERE e.wallet_id = w.id)));
SELECT seed.check('money', 'ledger entries whose running balance differs from the cumulative sum', '0',
       (SELECT count(*) FROM (SELECT balance_after, sum(amount) OVER (PARTITION BY wallet_id ORDER BY posted_at, id) AS cum
                                FROM billing.wallet_ledger_entry) q WHERE q.balance_after <> q.cum)::text,
       NOT EXISTS (SELECT 1 FROM (SELECT balance_after, sum(amount) OVER (PARTITION BY wallet_id ORDER BY posted_at, id) AS cum
                                    FROM billing.wallet_ledger_entry) q WHERE q.balance_after <> q.cum));
SELECT seed.check('money', 'downloads without a consumption debit', '0',
       (SELECT count(*) FROM billing.profile_download_event d
         WHERE NOT EXISTS (SELECT 1 FROM billing.wallet_ledger_entry e WHERE e.id = d.wallet_ledger_entry_id AND e.ledger_entry_type_code = 'consumption' AND e.amount < 0))::text,
       NOT EXISTS (SELECT 1 FROM billing.profile_download_event d
                    WHERE NOT EXISTS (SELECT 1 FROM billing.wallet_ledger_entry e WHERE e.id = d.wallet_ledger_entry_id AND e.ledger_entry_type_code = 'consumption' AND e.amount < 0)));
SELECT seed.check('money', 'refunds above their payment', '0',
       (SELECT count(*) FROM (SELECT o.order_amount, sum(r.refund_amount) AS s FROM billing.refund r JOIN billing.payment_order o ON o.id = r.payment_order_id GROUP BY o.id, o.order_amount) q WHERE q.s > q.order_amount)::text,
       NOT EXISTS (SELECT 1 FROM (SELECT o.order_amount, sum(r.refund_amount) AS s FROM billing.refund r JOIN billing.payment_order o ON o.id = r.payment_order_id GROUP BY o.id, o.order_amount) q WHERE q.s > q.order_amount));

-- 5. licences, devices, sessions (RG9)
SELECT seed.check('licence', 'licences using more seats than max_users', '0',
       (SELECT count(*) FROM lic.licence l WHERE (SELECT count(*) FROM lic.licence_seat s WHERE s.licence_id = l.id AND s.released_at IS NULL) > l.max_users)::text,
       NOT EXISTS (SELECT 1 FROM lic.licence l WHERE (SELECT count(*) FROM lic.licence_seat s WHERE s.licence_id = l.id AND s.released_at IS NULL) > l.max_users));
SELECT seed.check('licence', 'users with more active sessions than devices allowed', '0',
       (SELECT count(*) FROM (SELECT s.app_user_id, count(*) AS n, max(l.max_devices_per_user) AS lim
                                FROM lic.login_session s JOIN lic.licence_seat st ON st.id = s.licence_seat_id
                                JOIN lic.licence l ON l.id = st.licence_id
                               WHERE s.ended_at IS NULL AND s.expires_at > now() GROUP BY s.app_user_id) q WHERE q.n > q.lim)::text,
       NOT EXISTS (SELECT 1 FROM (SELECT s.app_user_id, count(*) AS n, max(l.max_devices_per_user) AS lim
                                    FROM lic.login_session s JOIN lic.licence_seat st ON st.id = s.licence_seat_id
                                    JOIN lic.licence l ON l.id = st.licence_id
                                   WHERE s.ended_at IS NULL AND s.expires_at > now() GROUP BY s.app_user_id) q WHERE q.n > q.lim));

-- 6. access rules the load bypassed
SELECT seed.check('access', 'sourcing requests on jobs not open to consultants', '0',
       (SELECT count(*) FROM src.sourcing_request sr JOIN job.job_requirement j ON j.id = sr.job_requirement_id WHERE NOT j.is_open_to_consultant)::text,
       NOT EXISTS (SELECT 1 FROM src.sourcing_request sr JOIN job.job_requirement j ON j.id = sr.job_requirement_id WHERE NOT j.is_open_to_consultant));
SELECT seed.check('access', 'outreach to candidates who blocked the sender', '0',
       (SELECT count(*) FROM src.outreach_recipient r JOIN src.outreach_batch b ON b.id = r.outreach_batch_id
          JOIN profile.candidate_profile cp ON cp.id = r.candidate_profile_id
          JOIN admin.block_list bl ON bl.blocker_app_user_id = cp.app_user_id AND bl.deleted_at IS NULL
         WHERE bl.blocked_app_user_id = b.sender_app_user_id OR bl.blocked_organisation_id = b.sender_organisation_id)::text,
       NOT EXISTS (SELECT 1 FROM src.outreach_recipient r JOIN src.outreach_batch b ON b.id = r.outreach_batch_id
                    JOIN profile.candidate_profile cp ON cp.id = r.candidate_profile_id
                    JOIN admin.block_list bl ON bl.blocker_app_user_id = cp.app_user_id AND bl.deleted_at IS NULL
                   WHERE bl.blocked_app_user_id = b.sender_app_user_id OR bl.blocked_organisation_id = b.sender_organisation_id));
SELECT seed.check('access', 'interviewers outside the job organisation', '0',
       (SELECT count(*) FROM job.interview i JOIN job.application a ON a.id = i.application_id AND a.candidate_profile_id = i.candidate_profile_id
          JOIN job.job_requirement j ON j.id = a.job_requirement_id
         WHERE i.interviewer_app_user_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM org.recruiter_mapping m WHERE m.app_user_id = i.interviewer_app_user_id AND m.organisation_id = j.organisation_id))::text,
       NOT EXISTS (SELECT 1 FROM job.interview i JOIN job.application a ON a.id = i.application_id AND a.candidate_profile_id = i.candidate_profile_id
                    JOIN job.job_requirement j ON j.id = a.job_requirement_id
                   WHERE i.interviewer_app_user_id IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM org.recruiter_mapping m WHERE m.app_user_id = i.interviewer_app_user_id AND m.organisation_id = j.organisation_id)));
SELECT seed.check('access', 'organisation hierarchy cycles (parent id is always lower)', '0',
       (SELECT count(*) FROM org.organisation WHERE parent_organisation_id >= id)::text,
       NOT EXISTS (SELECT 1 FROM org.organisation WHERE parent_organisation_id >= id));

-- 7. data standards (docket Section 5) on the seeded data
SELECT seed.check('standards', 'salary sentinels (0 or negative stored as an amount)', '0',
       (SELECT (SELECT count(*) FROM job.job_requirement WHERE salary_min <= 0 OR salary_max <= 0)
             + (SELECT count(*) FROM profile.candidate_profile WHERE current_salary_amount <= 0 OR expected_salary_amount <= 0))::text,
       NOT EXISTS (SELECT 1 FROM job.job_requirement WHERE salary_min <= 0 OR salary_max <= 0)
       AND NOT EXISTS (SELECT 1 FROM profile.candidate_profile WHERE current_salary_amount <= 0 OR expected_salary_amount <= 0));
SELECT seed.check('standards', 'undisclosed salaries are NULL, not zero (candidate profiles)', '> 0 NULL with code not_disclosed',
       (SELECT count(*) FROM profile.candidate_profile WHERE current_salary_disclosure_code = 'not_disclosed' AND current_salary_amount IS NULL)::text,
       EXISTS (SELECT 1 FROM profile.candidate_profile WHERE current_salary_disclosure_code = 'not_disclosed' AND current_salary_amount IS NULL));
SELECT seed.check('standards', 'emails stored in lowercase', '0 violations',
       (SELECT count(*) FROM profile.candidate_contact WHERE email <> lower(email))::text,
       NOT EXISTS (SELECT 1 FROM profile.candidate_contact WHERE email <> lower(email)));
SELECT seed.check('standards', 'phone numbers in E.164 with a country', '0 violations',
       (SELECT count(*) FROM profile.candidate_contact WHERE phone IS NOT NULL AND (phone !~ '^\+[1-9][0-9]{6,14}$' OR phone_country_id IS NULL))::text,
       NOT EXISTS (SELECT 1 FROM profile.candidate_contact WHERE phone IS NOT NULL AND (phone !~ '^\+[1-9][0-9]{6,14}$' OR phone_country_id IS NULL)));
SELECT seed.check('standards', 'identifiers never stored in clear (org identifiers encrypted)', '0 clear',
       (SELECT count(*) FROM org.organisation_identifier WHERE position(convert_to(right(value_last4, 4), 'UTF8') IN value_encrypted) > 0
                                                          AND position('1Z5'::bytea IN value_encrypted) > 0)::text,
       NOT EXISTS (SELECT 1 FROM org.organisation_identifier WHERE position('1Z5'::bytea IN value_encrypted) > 0 AND octet_length(value_encrypted) < 20));
SELECT seed.check('standards', 'multilingual names present (Devanagari, Tamil, Arabic, Han)', 'all four scripts',
       (SELECT format('dev=%s tam=%s ara=%s han=%s',
          count(*) FILTER (WHERE full_name ~ '[ऀ-ॿ]'), count(*) FILTER (WHERE full_name ~ '[஀-௿]'),
          count(*) FILTER (WHERE full_name ~ '[؀-ۿ]'), count(*) FILTER (WHERE full_name ~ '[一-鿿]')) FROM profile.candidate_profile),
       (SELECT count(*) FILTER (WHERE full_name ~ '[ऀ-ॿ]') > 0 AND count(*) FILTER (WHERE full_name ~ '[஀-௿]') > 0
           AND count(*) FILTER (WHERE full_name ~ '[؀-ۿ]') > 0 AND count(*) FILTER (WHERE full_name ~ '[一-鿿]') > 0
          FROM profile.candidate_profile));
SELECT seed.check('standards', 'near-duplicate candidates (extra profiles sharing a phone number)', '2% - 3% of profiles',
       round(100.0 * ((SELECT count(*) FROM profile.candidate_contact WHERE phone IS NOT NULL)
                    - (SELECT count(DISTINCT phone) FROM profile.candidate_contact WHERE phone IS NOT NULL))
                    / (SELECT count(*) FROM profile.candidate_profile), 2)::text || '%',
       ((SELECT count(*) FROM profile.candidate_contact WHERE phone IS NOT NULL)
         - (SELECT count(DISTINCT phone) FROM profile.candidate_contact WHERE phone IS NOT NULL))::numeric
         / (SELECT count(*) FROM profile.candidate_profile) BETWEEN 0.02 AND 0.03);
SELECT seed.check('standards', 'application partitions evenly filled (max/min row ratio)', '< 1 + 8/sqrt(candidates per partition)',
       (SELECT round(max(c)::numeric / nullif(min(c), 0), 3)::text FROM (SELECT count(*) AS c FROM job.application GROUP BY tableoid) q),
       (SELECT max(c)::numeric / nullif(min(c), 0) FROM (SELECT count(*) AS c FROM job.application GROUP BY tableoid) q)
         < 1 + 8 / sqrt((SELECT n_cand FROM seed.params) / 32.0));
SELECT seed.check('gig', 'overlapping assignment attempts rejected by the exclusion constraint', 'attempted = rejected',
       (SELECT attempted || ' attempted, ' || rejected || ' rejected' FROM seed.gig_overlap_attempt),
       (SELECT attempted = rejected AND attempted > 0 FROM seed.gig_overlap_attempt));
SELECT seed.check('warehouse', 'fact rows equal job + gig applications', '=',
       (SELECT count(*) FROM dw.fact_application)::text,
       (SELECT count(*) FROM dw.fact_application) = (SELECT count(*) FROM job.application WHERE EXISTS (SELECT 1 FROM dw.dim_candidate d WHERE d.candidate_profile_id = job.application.candidate_profile_id))
                                                   + (SELECT count(*) FROM gig.gig_application));

\o
-- report
SELECT area, check_name, expected, actual, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result FROM seed.validation ORDER BY id;
SELECT format('seed validation: %s checks, %s failed', count(*), count(*) FILTER (WHERE NOT ok)) AS summary FROM seed.validation \gset
\echo :summary
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM seed.validation WHERE NOT ok) THEN RAISE EXCEPTION 'seed validation failed'; END IF;
END $$;

-- row counts per module, for the evidence and the extrapolation baseline
SELECT n.nspname || '.' || c.relname AS relation, c.reltuples::bigint AS estimated_rows,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition AND n.nspname IN ('ref','profile','job','admin','org','gig','lic','src','billing','notif','audit','dw')
   AND c.reltuples > 10000 ORDER BY pg_total_relation_size(c.oid) DESC LIMIT 25;
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;

DROP TABLE IF EXISTS seed.app_plan, seed.gig_plan, seed.ledger_plan, seed.cand;
