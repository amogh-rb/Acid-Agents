-- M19 seed, step 1 (Administration + Organisation): accounts, organisations, users, roles, credentials, consent,
-- recruiter mapping, locations, encrypted identifiers, verification.
\ir _preamble.sql

-- ---------------------------------------------------------------------------------------------------
-- Organisations. Type by id range: 55% employer, 15% staffing agency, 20% client, 6% consultancy, 4% campus.
CREATE TEMP TABLE tmp_org_names AS
SELECT i AS idx, a.adjective, n.noun, s.suffix
  FROM generate_series(1, 16) i,
       LATERAL (SELECT (ARRAY['Apex','Bright','Cobalt','Delta','Evergreen','Falcon','Global','Horizon','Infinity','Juniper','Keystone','Lumen','Meridian','Nova','Orbit','Pinnacle'])[i] adjective) a,
       LATERAL (SELECT (ARRAY['Systems','Labs','Logistics','Foods','Motors','Health','Finance','Retail','Infra','Textiles','Analytics','Energy','Education','Staffing','Consulting','Networks'])[i] noun) n,
       LATERAL (SELECT (ARRAY['Pvt Ltd','Limited','LLP','Inc'])[1 + i % 4] suffix) s;

INSERT INTO org.account (id, account_name, account_status_code, billing_email, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT o, (SELECT adjective FROM tmp_org_names WHERE idx = 1 + (o % 16)) || ' ' ||
          (SELECT noun FROM tmp_org_names WHERE idx = 1 + ((o / 16) % 16)) || ' ' || to_char(o, 'FM00000'),
       (ARRAY['active','active','active','active','active','active','active','active','trial','trial','suspended','closed'])[1 + (o % 12)],
       'billing' || o || '@accounts.example',
       now() - make_interval(days => 400 + (seed.h(o, 1) * 600)::int),
       now() - make_interval(days => (seed.h(o, 2) * 300)::int)
  FROM generate_series(1, (SELECT n_hiring FROM seed.params)) o;

INSERT INTO org.organisation (id, organisation_name, organisation_status_code, legal_name, organisation_type_code, account_id,
                              parent_organisation_id, industry_id, employee_count_band_code, website_url, verification_status_code,
                              created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT o.id,
       n.adjective || ' ' || n.noun || ' ' || to_char(o.id, 'FM00000'),
       (ARRAY['active','active','active','active','active','active','active','pending_verification','suspended','closed'])[1 + (o.id % 10)],
       CASE WHEN o.id % 3 = 0 THEN NULL
            ELSE n.adjective || ' ' || n.noun || ' ' || to_char(o.id, 'FM00000') || ' ' || n.suffix END,
       CASE WHEN o.id <= 0.55 * p.n_org THEN 'employer'
            WHEN o.id <= 0.70 * p.n_org THEN 'staffing_agency'
            WHEN o.id <= 0.90 * p.n_org THEN 'client'
            WHEN o.id <= 0.96 * p.n_org THEN 'consultancy'
            ELSE 'campus' END,
       CASE WHEN o.id <= p.n_hiring THEN o.id END,
       CASE WHEN o.id > 10 AND seed.h(o.id, 3) < 0.10 THEN 1 + floor(seed.h(o.id, 4) * (o.id - 1))::bigint END,
       (SELECT id FROM (SELECT id, row_number() OVER (ORDER BY id) rn FROM ref.industry) i
         WHERE rn = 1 + (o.id % (SELECT count(*) FROM ref.industry))),
       (ARRAY['size_1_10','size_11_50','size_51_200','size_201_1000','size_1001_10000','size_10001_plus'])[seed.wpick(o.id, 5, ARRAY[0.15,0.40,0.70,0.88,0.97,1.0])],
       CASE WHEN o.id % 5 = 0 THEN NULL ELSE 'https://www.' || lower(n.adjective || n.noun) || o.id || '.example' END,
       (ARRAY['verified','verified','verified','verified','verified','verified','verified','pending','pending','failed','expired'])[1 + (o.id % 11)],
       now() - make_interval(days => 400 + (seed.h(o.id, 1) * 600)::int),
       now() - make_interval(days => (seed.h(o.id, 2) * 300)::int)
  FROM generate_series(1, (SELECT n_org FROM seed.params)) o(id)
  CROSS JOIN seed.params p
  JOIN tmp_org_names n ON n.idx = 1 + (o.id % 16)
  ;
-- names above use the adjective of idx; keep the account name consistent with the organisation name
UPDATE org.account a SET account_name = o.organisation_name FROM org.organisation o WHERE o.id = a.id;

INSERT INTO org.organisation_location (organisation_id, location_name, address_line1, city_id, postal_code, latitude, longitude, is_headquarters,
                                       created_at, updated_at)
SELECT o.id, c.city_name || CASE WHEN k = 1 THEN ' HQ' ELSE ' Office ' || k END,
       (10 + (seed.h(o.id * 7 + k, 1) * 489)::int) || ' ' || (ARRAY['MG Road','Anna Salai','Park Street','Brigade Road','Linking Road','Residency Road'])[1 + (o.id + k) % 6],
       c.id, to_char(100000 + (o.id * 37 + k) % 899999, 'FM000000'), c.latitude, c.longitude, k = 1, o.created_at, o.created_at
  FROM org.organisation o
  CROSS JOIN LATERAL generate_series(1, CASE WHEN o.id % 4 = 0 THEN 2 ELSE 1 END) k
  JOIN LATERAL (SELECT id, city_name, latitude, longitude FROM ref.city ORDER BY id OFFSET ((o.id + k) % (SELECT count(*) FROM ref.city)) LIMIT 1) c ON true
 WHERE o.account_id IS NOT NULL OR o.organisation_type_code IN ('consultancy', 'campus');

-- GSTIN-like identifiers (valid format), encrypted with a demo key; unique by HMAC (type, hash)
INSERT INTO org.organisation_identifier (organisation_id, identifier_type_code, value_encrypted, value_hash, value_last4,
                                         verification_status_code, verified_at, created_at, updated_at)
SELECT o.id, 'gstin', pgp_sym_encrypt(g.v, 'seed-demo-key'), hmac(g.v, 'seed-demo-key', 'sha256'), right(g.v, 4),
       CASE WHEN o.verification_status_code = 'verified' THEN 'verified' ELSE 'pending' END,
       CASE WHEN o.verification_status_code = 'verified' THEN o.created_at + interval '3 days' END,
       o.created_at, o.created_at
  FROM org.organisation o
  CROSS JOIN LATERAL (SELECT lpad(((o.id % 37) + 1)::text, 2, '0')
                              || chr((65 + (o.id / 10000) % 26)::int) || chr((65 + (o.id / 260000) % 26)::int) || chr((65 + (o.id / 6760000) % 26)::int)
                              || chr((65 + (o.id / 100) % 26)::int) || chr((65 + (o.id / 7) % 26)::int)
                              || lpad((o.id % 10000)::text, 4, '0') || chr((65 + o.id % 26)::int) || '1Z5' AS v) g
 WHERE o.account_id IS NOT NULL AND o.id % 7 <> 0;

INSERT INTO org.verification (organisation_id, verification_kind_code, organisation_identifier_id, verification_status_code,
                              idempotency_key, provider_reference, requested_at, completed_at, created_at, updated_at)
SELECT o.id, 'tax_registration', i.id,
       CASE WHEN o.verification_status_code = 'verified' THEN 'verified' ELSE 'pending' END,
       'seed-verif-' || o.id,
       CASE WHEN o.verification_status_code = 'verified' THEN 'prov-' || o.id END,
       o.created_at + interval '1 day',
       CASE WHEN o.verification_status_code = 'verified' THEN o.created_at + interval '3 days' END,
       o.created_at, o.created_at
  FROM org.organisation o JOIN org.organisation_identifier i ON i.organisation_id = o.id;

-- ---------------------------------------------------------------------------------------------------
-- Users. Ranges: 1 system, 2-6 admins, candidates, recruiters, consultants, gig workers, individual requesters.
INSERT INTO admin.app_user (id, user_status_code, login_email, login_phone, login_phone_country_id, display_name, last_login_at, deleted_at,
                            created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT u.id,
       CASE WHEN seed.h(u.id, 11) < 0.93 THEN 'active' WHEN seed.h(u.id, 11) < 0.97 THEN 'pending_verification'
            WHEN seed.h(u.id, 11) < 0.985 THEN 'suspended' ELSE 'deactivated' END,
       'u' || u.id || '@' || (ARRAY['mail.example','post.example','inbox.example','work.example'])[1 + u.id % 4],
       CASE WHEN seed.h(u.id, 12) < 0.60 THEN '+91' || (7000000000 + u.id)::text END,
       CASE WHEN seed.h(u.id, 12) < 0.60 THEN (SELECT id FROM ref.country WHERE iso_alpha2 = 'IN') END,
       CASE WHEN u.id <= p.u_cand OR u.id > p.u_rec AND u.id <= p.u_rec + p.n_rec + p.n_consult
                 OR u.id > p.u_consult + p.n_consult
            THEN (SELECT latin FROM seed.name_pool WHERE locale = 'en' AND kind = 'g' AND ord = 1 + (u.id % 16)) || ' ' ||
                 (SELECT latin FROM seed.name_pool WHERE locale = 'en' AND kind = 'f' AND ord = 1 + ((u.id / 16) % 16)) END,
       CASE WHEN seed.h(u.id, 13) < 0.85 THEN now() - make_interval(hours => (seed.h(u.id, 14) * 4000)::int) END,
       CASE WHEN seed.h(u.id, 15) < 0.01 THEN now() - interval '30 days' END,
       now() - make_interval(days => 560 + (seed.h(u.id, 16) * 400)::int),
       now() - make_interval(days => (seed.h(u.id, 17) * 30)::int)
  FROM generate_series(2, (SELECT n_user FROM seed.params)) u(id) CROSS JOIN seed.params p;

-- roles (effective-dated; organisation-scoped for recruiters and employers)
INSERT INTO admin.user_role (app_user_id, app_role_code, organisation_id, valid_period)
SELECT u, CASE WHEN u <= 3 THEN 'super_admin' ELSE 'admin' END, NULL::bigint, tstzrange(timestamptz '2025-01-01', NULL)
  FROM generate_series(2, 6) u
UNION ALL
SELECT u, 'candidate', NULL, tstzrange(timestamptz '2025-01-01', NULL)
  FROM generate_series((SELECT u_cand + 1 FROM seed.params), (SELECT u_cand + n_cand FROM seed.params)) u
UNION ALL
SELECT p.u_rec + k, 'recruiter', ((k - 1) % p.n_hiring) + 1, tstzrange(timestamptz '2025-01-01', NULL)
  FROM seed.params p, generate_series(1, (SELECT n_rec FROM seed.params)) k
UNION ALL
SELECT p.u_rec + k, 'employer', k, tstzrange(timestamptz '2025-01-01', NULL)
  FROM seed.params p, generate_series(1, (SELECT n_hiring FROM seed.params)) k
UNION ALL
SELECT p.u_consult + k, 'consultant', NULL, tstzrange(timestamptz '2025-01-01', NULL)
  FROM seed.params p, generate_series(1, (SELECT n_consult FROM seed.params)) k
UNION ALL
SELECT p.u_gw + k, 'gig_worker', NULL, tstzrange(timestamptz '2025-01-01', NULL)
  FROM seed.params p, generate_series(1, (SELECT n_gw FROM seed.params)) k;

-- Recruiter mapping: current organisation from 2025-01-01; 10% have a closed earlier mapping (back-to-back)
INSERT INTO org.recruiter_mapping (app_user_id, organisation_id, valid_period)
SELECT p.u_rec + k, ((k - 1) % p.n_hiring) + 1, daterange(date '2025-01-01', NULL)
  FROM seed.params p, generate_series(1, (SELECT n_rec FROM seed.params)) k
UNION ALL
SELECT p.u_rec + k, ((k + 2) % p.n_hiring) + 1, daterange(date '2023-01-01', date '2025-01-01')
  FROM seed.params p, generate_series(1, (SELECT n_rec FROM seed.params)) k
 WHERE ((k + 2) % p.n_hiring) + 1 <> ((k - 1) % p.n_hiring) + 1 AND seed.h(k, 21) < 0.10;

INSERT INTO org.account_administrator (account_id, app_user_id, is_primary)
SELECT a.id, p.u_rec + a.id, true FROM org.account a CROSS JOIN seed.params p WHERE a.id <= p.n_hiring;

-- credentials (synthetic PHC-format hashes: structurally valid, not crackable passwords)
INSERT INTO admin.user_credential (app_user_id, password_hash, hash_algorithm_code, password_changed_at, failed_attempt_count,
                                   must_change_password, created_at, updated_at)
SELECT id, '$argon2id$v=19$m=65536,t=3,p=4$' || substr(md5(id::text), 1, 22) || '$' || md5(id::text || 'x'), 'argon2id',
       created_at + interval '1 hour', (seed.h(id, 31) * 3)::smallint, seed.h(id, 32) < 0.02, created_at, created_at
  FROM admin.app_user WHERE id > 1;

-- consent: every user accepts the terms; 40% opt in to marketing email, 5% of those later withdraw
INSERT INTO admin.consent_record (app_user_id, consent_purpose_code, is_granted, policy_version, recorded_at, client_ip_masked)
SELECT id, 'terms_of_service', true, '2026.1', created_at + interval '1 minute', '203.0.113.x' FROM admin.app_user WHERE id > 1
UNION ALL
SELECT id, 'marketing_email', true, '2026.1', created_at + interval '2 minutes', NULL FROM admin.app_user WHERE id > 1 AND seed.h(id, 41) < 0.40
UNION ALL
SELECT id, 'marketing_email', false, '2026.1', created_at + interval '60 days', NULL
  FROM admin.app_user WHERE id > 1 AND seed.h(id, 41) < 0.40 AND seed.h(id, 42) < 0.05 AND created_at + interval '60 days' < now();

SELECT count(*) AS organisations FROM org.organisation \gset
SELECT count(*) AS users FROM admin.app_user \gset
\echo organisations=:organisations users=:users
