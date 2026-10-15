-- M19 seed, step 2 (Profile): candidate profiles with duplicates and multilingual names, and their children.
\ir _preamble.sql

CREATE TABLE seed.refs AS
SELECT (SELECT array_agg(id ORDER BY id) FROM ref.city)          AS cities,
       (SELECT array_agg(id ORDER BY id) FROM ref.skill)         AS skills,
       (SELECT array_agg(id ORDER BY id) FROM ref.qualification) AS quals,
       (SELECT array_agg(id ORDER BY id) FROM ref.field_of_study) AS fields,
       (SELECT array_agg(id ORDER BY id) FROM ref.institution)   AS institutions,
       (SELECT array_agg(id ORDER BY id) FROM ref.industry)      AS industries,
       (SELECT array_agg(id ORDER BY id) FROM ref.job_role)      AS roles,
       (SELECT array_agg(role_name ORDER BY id) FROM ref.job_role) AS role_names,
       (SELECT array_agg(id ORDER BY id) FROM ref.language)      AS languages,
       (SELECT id FROM ref.country WHERE iso_alpha2 = 'IN')      AS india,
       (SELECT id FROM ref.language WHERE code = 'en')           AS lang_en;

-- ---------------------------------------------------------------------------------------------------
-- Profiles. ~3.5% are near-duplicates (about 2.5% detectable by a shared phone number) of an earlier candidate: same person, transliterated (Latin) name, same phone.
CREATE UNLOGGED TABLE seed.cand AS
WITH c AS (
  SELECT n,
         (n > 1000 AND seed.h(n, 50) < 0.035) AS is_dup,
         CASE WHEN n > 1000 AND seed.h(n, 50) < 0.035 THEN 1 + floor(seed.h(n, 51) * (n - 1))::bigint ELSE n END AS base_n
    FROM generate_series(1, (SELECT n_cand FROM seed.params)) n
)
SELECT c.n, c.is_dup, c.base_n,
       lm.locale, lm.language_code,
       gp.native AS g_native, gp.latin AS g_latin, fp.native AS f_native, fp.latin AS f_latin
  FROM c
  JOIN seed.locale_mix lm ON lm.idx = (SELECT min(idx) FROM seed.locale_mix WHERE seed.h(c.base_n, 52) < cum)
  JOIN seed.name_pool gp ON gp.locale = lm.locale AND gp.kind = 'g' AND gp.ord = 1 + floor(seed.h(c.base_n, 53) * 16)::int
  JOIN seed.name_pool fp ON fp.locale = lm.locale AND fp.kind = 'f' AND fp.ord = 1 + floor(seed.h(c.base_n, 54) * 16)::int;
ALTER TABLE seed.cand ADD PRIMARY KEY (n);

INSERT INTO profile.candidate_profile (id, app_user_id, full_name, given_name, family_name, date_of_birth, gender_code,
       nationality_country_id, current_city_id, headline, summary, summary_language_id, total_experience_months,
       current_salary_disclosure_code, current_salary_amount, expected_salary_disclosure_code, expected_salary_amount,
       currency_code, pay_period_code, notice_period_code, is_open_to_work, legacy_source_system, legacy_source_id,
       created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT c.n, p.u_cand + c.n,
       CASE WHEN c.locale = 'zh' THEN fam || giv ELSE giv || ' ' || fam END,
       giv, fam,
       CASE WHEN seed.h(c.n, 60) < 0.70 THEN date '1965-01-01' + (seed.h(c.n, 61) * 14600)::int END,
       CASE WHEN seed.h(c.n, 62) < 0.15 THEN NULL
            ELSE (ARRAY['female','male','female','male','non_binary','prefer_not_to_say'])[seed.wpick(c.n, 63, ARRAY[0.40,0.78,0.80,0.81,0.82,1.0]) ] END,
       CASE WHEN seed.h(c.n, 64) < 0.92 THEN r.india END,
       r.cities[1 + floor(power(seed.h(c.n, 65), 1.7) * array_length(r.cities, 1))::int],
       CASE WHEN seed.h(c.n, 66) < 0.70 THEN r.role_names[1 + floor(seed.h(c.n, 67) * array_length(r.role_names, 1))::int] || ' | ' || exp.months / 12 || ' yrs' END,
       CASE WHEN seed.h(c.n, 68) < 0.60 THEN 'Professional with ' || exp.months / 12 || ' years of experience, open to new roles.' END,
       CASE WHEN seed.h(c.n, 68) < 0.60 THEN (SELECT id FROM ref.language WHERE code = c.language_code) END,
       exp.months,
       CASE WHEN sal.cur IS NOT NULL THEN 'disclosed' WHEN exp.months = 0 THEN 'not_applicable' ELSE 'not_disclosed' END, sal.cur,
       CASE WHEN sal.exp IS NOT NULL THEN 'disclosed' ELSE 'not_disclosed' END, sal.exp,
       CASE WHEN sal.cur IS NOT NULL OR sal.exp IS NOT NULL THEN 'INR' END,
       CASE WHEN sal.cur IS NOT NULL OR sal.exp IS NOT NULL THEN 'annual' END,
       CASE WHEN seed.h(c.n, 69) < 0.60 THEN (ARRAY['immediate','days_15','days_30','days_60','days_90','serving_notice'])[1 + (c.n % 6)] END,
       seed.h(c.n, 70) < 0.80,
       CASE WHEN seed.h(c.n, 71) < 0.10 THEN 'legacy_naukri_export' END,
       CASE WHEN seed.h(c.n, 71) < 0.10 THEN 'LN-' || c.n END,
       now() - make_interval(days => 560 + (seed.h(p.u_cand + c.n, 16) * 400)::int),
       now() - make_interval(days => (seed.h(c.n, 72) * 30)::int)
  FROM seed.cand c
  CROSS JOIN seed.params p
  CROSS JOIN seed.refs r
  CROSS JOIN LATERAL (SELECT CASE WHEN c.is_dup THEN c.g_latin ELSE c.g_native END AS giv,
                             CASE WHEN c.is_dup THEN c.f_latin ELSE c.f_native END AS fam) nm
  CROSS JOIN LATERAL (SELECT floor(power(seed.h(c.n, 73), 1.6) * 240)::int AS months) exp
  CROSS JOIN LATERAL (SELECT CASE WHEN seed.h(c.n, 74) < 0.35 THEN (round((300000 + seed.h(c.n, 75) * 2700000) / 1000) * 1000)::numeric END AS cur,
                             CASE WHEN seed.h(c.n, 76) < 0.50 THEN (round((350000 + seed.h(c.n, 77) * 3200000) / 1000) * 1000)::numeric END AS exp) sal;

-- contacts: email (login email, unique) for everyone; phone for 80% (near-duplicates share the base candidate's phone)
INSERT INTO profile.candidate_contact (candidate_profile_id, contact_type_code, email, is_primary, is_verified, verified_at, created_at, updated_at)
SELECT cp.id, 'email', u.login_email, true, seed.h(cp.id, 80) < 0.70,
       CASE WHEN seed.h(cp.id, 80) < 0.70 THEN cp.created_at + interval '1 hour' END, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp JOIN admin.app_user u ON u.id = cp.app_user_id;

INSERT INTO profile.candidate_contact (candidate_profile_id, contact_type_code, phone, phone_country_id, is_primary, is_verified, verified_at,
                                       created_at, updated_at)
SELECT cp.id, 'phone', '+91' || (8000000000 + c.base_n)::text, r.india, true, seed.h(cp.id, 81) < 0.50,
       CASE WHEN seed.h(cp.id, 81) < 0.50 THEN cp.created_at + interval '2 hours' END, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp
  JOIN seed.cand c ON c.n = cp.id CROSS JOIN seed.refs r
 WHERE seed.h(c.base_n, 82) < 0.80;   -- phone presence follows the base person, so duplicates share it

INSERT INTO profile.candidate_address (candidate_profile_id, address_type_code, address_line1, locality, city_id, postal_code, created_at, updated_at)
SELECT cp.id, 'current', (1 + (cp.id % 400)) || ' ' || (ARRAY['Gandhi Road','Nehru Street','Temple Road','Lake View','Station Road'])[1 + cp.id % 5],
       (ARRAY['Anna Nagar','Whitefield','Andheri','Salt Lake','Banjara Hills'])[1 + cp.id % 5], cp.current_city_id,
       to_char(100000 + (cp.id * 13) % 899999, 'FM000000'), cp.created_at, cp.created_at
  FROM profile.candidate_profile cp WHERE cp.current_city_id IS NOT NULL AND seed.h(cp.id, 83) < 0.60;

-- education (one row for 85%; secondary-school entries carry no field of study)
INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, field_of_study_id, institution_id, institution_name,
                                         study_mode_code, start_date, end_date, score_pct, grade_text, is_highest, created_at, updated_at)
SELECT cp.id, q.qid, CASE WHEN q.is_school THEN NULL ELSE r.fields[1 + floor(seed.h(cp.id, 91) * array_length(r.fields, 1))::int] END,
       CASE WHEN seed.h(cp.id, 92) < 0.50 THEN r.institutions[1 + floor(seed.h(cp.id, 93) * array_length(r.institutions, 1))::int] END,
       CASE WHEN seed.h(cp.id, 92) >= 0.50 THEN 'Local College ' || (cp.id % 900) END,
       (ARRAY['full_time','full_time','full_time','part_time','distance'])[1 + cp.id % 5],
       d.start_d, CASE WHEN seed.h(cp.id, 94) < 0.92 THEN d.start_d + (365 * 3 + (seed.h(cp.id, 95) * 365)::int) END,
       CASE WHEN seed.h(cp.id, 96) < 0.60 THEN round((50 + seed.h(cp.id, 97) * 48)::numeric, 2) END,
       CASE WHEN seed.h(cp.id, 96) >= 0.60 AND seed.h(cp.id, 98) < 0.50 THEN (6 + seed.h(cp.id, 99) * 3.9)::numeric(3,1)::text || ' CGPA' END,
       true, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp
  CROSS JOIN seed.refs r
  CROSS JOIN LATERAL (SELECT r.quals[1 + floor(seed.h(cp.id, 90) * array_length(r.quals, 1))::int] AS qid) q0
  CROSS JOIN LATERAL (SELECT q0.qid AS qid, (SELECT qualification_level_code IN ('secondary', 'higher_secondary') FROM ref.qualification WHERE id = q0.qid) AS is_school) q
  CROSS JOIN LATERAL (SELECT date '2005-06-01' + (seed.h(cp.id, 89) * 3650)::int AS start_d) d
 WHERE seed.h(cp.id, 88) < 0.85;

-- work experience: current job (and a previous one for 5+ years), employer text or a registered organisation
INSERT INTO profile.candidate_work_experience (candidate_profile_id, organisation_id, employer_name, designation, job_role_id, industry_id,
                                               employment_type_code, city_id, start_date, end_date, is_current, created_at, updated_at)
SELECT cp.id,
       CASE WHEN seed.h(cp.id * 3 + k, 100) < 0.30 THEN 1 + floor(seed.h(cp.id * 3 + k, 101) * (SELECT n_hiring FROM seed.params))::bigint END,
       CASE WHEN seed.h(cp.id * 3 + k, 100) >= 0.30 THEN (ARRAY['Zenith Soft','BlueOcean Traders','Kaveri Textiles','Orion Logistics','Sapphire Bank','Mango Retail'])[1 + (cp.id + k) % 6] END,
       r.role_names[1 + floor(seed.h(cp.id * 3 + k, 102) * array_length(r.role_names, 1))::int],
       r.roles[1 + floor(seed.h(cp.id * 3 + k, 102) * array_length(r.roles, 1))::int],
       r.industries[1 + floor(seed.h(cp.id * 3 + k, 103) * array_length(r.industries, 1))::int],
       (ARRAY['permanent','permanent','permanent','contract','internship'])[1 + (cp.id + k) % 5],
       cp.current_city_id,
       x.start_d, x.end_d, x.end_d IS NULL, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp
  CROSS JOIN seed.refs r
  CROSS JOIN LATERAL generate_series(1, CASE WHEN cp.total_experience_months > 60 THEN 2 ELSE 1 END) k
  CROSS JOIN LATERAL (
      SELECT CASE WHEN k = 1 THEN current_date - (cp.total_experience_months / 2 * 30 + 30)
                  ELSE current_date - (cp.total_experience_months * 30 + 60) END AS start_d,
             CASE WHEN k = 1 THEN CASE WHEN seed.h(cp.id, 104) < 0.60 THEN NULL ELSE current_date - 30 END
                  ELSE current_date - (cp.total_experience_months / 2 * 30 + 31) END AS end_d) x
 WHERE cp.total_experience_months > 0 AND x.start_d <= coalesce(x.end_d, current_date);

-- skills (about 3 per candidate, skewed towards popular skills), languages, preferences
INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id, proficiency_level_code, experience_months, last_used_year, created_at, updated_at)
SELECT cp.id, r.skills[1 + floor(power(seed.h(cp.id * 5 + k, 110), 1.4) * array_length(r.skills, 1))::int],
       (ARRAY['beginner','intermediate','intermediate','advanced','expert'])[1 + (cp.id + k) % 5],
       CASE WHEN seed.h(cp.id * 5 + k, 111) < 0.7 THEN (seed.h(cp.id * 5 + k, 112) * 120)::int END,
       2018 + (seed.h(cp.id * 5 + k, 113) * 8)::int, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp CROSS JOIN seed.refs r CROSS JOIN generate_series(1, 3) k
ON CONFLICT DO NOTHING;

INSERT INTO profile.candidate_language (candidate_profile_id, language_id, proficiency_level_code, created_at, updated_at)
SELECT cp.id, (SELECT id FROM ref.language WHERE code = c.language_code), 'expert', cp.created_at, cp.created_at
  FROM profile.candidate_profile cp JOIN seed.cand c ON c.n = cp.id;
INSERT INTO profile.candidate_language (candidate_profile_id, language_id, proficiency_level_code, created_at, updated_at)
SELECT cp.id, r.lang_en, 'advanced', cp.created_at, cp.created_at
  FROM profile.candidate_profile cp JOIN seed.cand c ON c.n = cp.id CROSS JOIN seed.refs r
 WHERE c.locale <> 'en' AND seed.h(cp.id, 120) < 0.70;

INSERT INTO profile.candidate_preferred_location (candidate_profile_id, city_id, created_at, updated_at)
SELECT cp.id, r.cities[1 + floor(power(seed.h(cp.id, 121), 1.7) * array_length(r.cities, 1))::int], cp.created_at, cp.created_at
  FROM profile.candidate_profile cp CROSS JOIN seed.refs r;
INSERT INTO profile.candidate_preferred_role (candidate_profile_id, job_role_id, created_at, updated_at)
SELECT cp.id, r.roles[1 + floor(seed.h(cp.id, 122) * array_length(r.roles, 1))::int], cp.created_at, cp.created_at
  FROM profile.candidate_profile cp CROSS JOIN seed.refs r;

INSERT INTO profile.candidate_web_link (candidate_profile_id, web_link_type_code, link_url, created_at, updated_at)
SELECT id, 'github', 'https://github.example/u' || id, created_at, created_at FROM profile.candidate_profile WHERE seed.h(id, 123) < 0.15;

INSERT INTO profile.candidate_certification (candidate_profile_id, certification_name, issuing_body, skill_id, issue_date, expiry_date,
                                             credential_reference, created_at, updated_at)
SELECT cp.id, (ARRAY['AWS Certified Cloud Practitioner','PMP','Google Data Analytics','Tally Professional','CNC Operator Level 2'])[1 + cp.id % 5],
       (ARRAY['Amazon','PMI','Google','Tally Education','NSDC'])[1 + cp.id % 5],
       r.skills[1 + (cp.id % array_length(r.skills, 1))], current_date - ((400 + cp.id % 900)::int),
       CASE WHEN cp.id % 3 = 0 THEN current_date + ((cp.id % 700)::int) END, 'CRED-' || cp.id, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp CROSS JOIN seed.refs r WHERE seed.h(cp.id, 124) < 0.08;

INSERT INTO profile.candidate_project (candidate_profile_id, project_kind_code, project_title, project_role, start_date, end_date, outcome,
                                       created_at, updated_at)
SELECT cp.id, (ARRAY['employment','academic','personal','gig'])[1 + cp.id % 4], 'Project ' || (cp.id % 5000),
       (ARRAY['Developer','Lead','Analyst','Coordinator'])[1 + cp.id % 4], current_date - ((500 + cp.id % 700)::int),
       CASE WHEN cp.id % 4 <> 0 THEN current_date - ((100 + cp.id % 300)::int) END,
       CASE WHEN cp.id % 3 = 0 THEN 'Delivered on time with positive feedback' END, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp WHERE seed.h(cp.id, 125) < 0.15;

-- resumes (default version per profile for 70%), national id references (tokens and hashes only), completion scores
INSERT INTO profile.resume_template (template_name, language_id, layout_definition)
SELECT 'Classic ' || l.code, l.id, '{"sections": ["summary", "experience", "education", "skills"]}'::jsonb
  FROM ref.language l WHERE l.is_ui_supported;

INSERT INTO profile.resume_version (candidate_profile_id, resume_template_id, version_number, version_label, body, body_language_id, is_default,
                                    created_at, updated_at)
SELECT cp.id, (SELECT min(id) FROM profile.resume_template), 1, 'Main resume',
       cp.full_name || E'\n' || coalesce(cp.headline, '') || E'\n' || coalesce(cp.summary, '') ||
       E'\nSkills: ' || (ARRAY['SQL','Excel','Welding','Sales','Java','Python','Tally','Customer service'])[1 + cp.id % 8] ||
       E'\nEducation and experience on request.',
       cp.summary_language_id, true, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp WHERE seed.h(cp.id, 130) < 0.70;

INSERT INTO profile.candidate_identity_document (candidate_profile_id, identifier_type_code, verification_token, identifier_hash,
                                                 identifier_last4, verification_status_code, verified_at, created_at, updated_at)
SELECT id, 'aadhaar', 'tok_' || md5(id::text), digest('aadhaar:' || id::text, 'sha256'), to_char(1000 + (id * 7919) % 9000, 'FM0000'),
       'verified', created_at + interval '1 day', created_at, created_at
  FROM profile.candidate_profile WHERE seed.h(id, 131) < 0.20;

INSERT INTO profile.profile_completion_score (candidate_profile_id, completion_pct, missing_sections, created_at, updated_at)
SELECT cp.id, round((35 + 65 * seed.h(cp.id, 132))::numeric, 2),
       CASE WHEN seed.h(cp.id, 132) > 0.7 THEN ARRAY[]::varchar[] ELSE ARRAY['certifications', 'projects']::varchar[] END,
       cp.created_at, cp.created_at
  FROM profile.candidate_profile cp;

-- assessments and courses (catalogue) with attempts and enrolments
INSERT INTO profile.assessment (assessment_name, assessment_type_code, skill_id, max_score, duration_minutes)
SELECT s.skill_name || ' proficiency test', 'skill_test', s.id, 100, 30 FROM (SELECT id, skill_name FROM ref.skill ORDER BY id LIMIT 12) s;
INSERT INTO profile.course (course_title, provider_name, skill_id, course_url, duration_hours)
SELECT 'Foundations of ' || s.skill_name, (ARRAY['NPTEL','Coursera','Skill India','Udemy'])[1 + s.id % 4], s.id,
       'https://learn.example/' || s.id, 10 + s.id % 40
  FROM (SELECT id, skill_name FROM ref.skill ORDER BY id LIMIT 10) s;

INSERT INTO profile.assessment_attempt (assessment_id, candidate_profile_id, started_at, submitted_at, raw_score, score_pct, created_at)
SELECT a.id, cp.id, t.started, t.started + interval '25 minutes', t.score, t.score, t.started + interval '25 minutes'
  FROM profile.candidate_profile cp
  JOIN LATERAL (SELECT id FROM profile.assessment ORDER BY id OFFSET (cp.id % 12) LIMIT 1) a ON true
  CROSS JOIN LATERAL (SELECT now() - make_interval(days => 1 + (seed.h(cp.id, 140) * 300)::int) AS started,
                             round((20 + 80 * seed.h(cp.id, 141))::numeric, 2) AS score) t
 WHERE seed.h(cp.id, 142) < 0.15;

INSERT INTO profile.course_enrolment (course_id, candidate_profile_id, enrolment_status_code, enrolled_on, completed_on, certificate_url,
                                      created_at, updated_at)
SELECT c.id, cp.id, CASE WHEN done THEN 'completed' ELSE (ARRAY['enrolled','in_progress','dropped'])[1 + cp.id % 3] END,
       current_date - ((60 + cp.id % 300)::int), CASE WHEN done THEN current_date - ((10 + cp.id % 50)::int) END,
       CASE WHEN done THEN 'https://learn.example/cert/' || cp.id END, cp.created_at, cp.created_at
  FROM profile.candidate_profile cp
  JOIN LATERAL (SELECT id FROM profile.course ORDER BY id OFFSET (cp.id % 10) LIMIT 1) c ON true
  CROSS JOIN LATERAL (SELECT seed.h(cp.id, 143) < 0.4 AS done) d
 WHERE seed.h(cp.id, 144) < 0.10;

-- history: profile views, activity log, bookmarks, referrals (append-only)
INSERT INTO profile.profile_view_event (candidate_profile_id, viewer_app_user_id, viewer_organisation_id, viewed_at)
SELECT 1 + (v % p.n_cand), p.u_rec + 1 + (v % p.n_rec), 1 + (v % p.n_rec) % p.n_hiring,
       now() - make_interval(mins => (seed.h(v, 150) * 525600)::int)
  FROM seed.params p, generate_series(1, (SELECT n_cand FROM seed.params)) v;

INSERT INTO profile.candidate_activity_event (candidate_profile_id, activity_event_type_code, occurred_at)
SELECT 1 + floor(seed.h(v, 151) * p.n_cand)::bigint,
       (ARRAY['login','login','login','profile_update','resume_download','job_apply'])[1 + v % 6],
       now() - make_interval(mins => (seed.h(v, 152) * 525600)::int)
  FROM seed.params p, generate_series(1, (SELECT n_cand FROM seed.params)) v;

INSERT INTO profile.candidate_bookmark_event (candidate_profile_id, actor_app_user_id, actor_organisation_id, bookmark_action_code, occurred_at)
SELECT 1 + floor(seed.h(v, 153) * p.n_cand)::bigint, p.u_rec + 1 + (v % p.n_rec), 1 + (v % p.n_rec) % p.n_hiring,
       CASE WHEN v % 5 = 0 THEN 'removed' ELSE 'added' END, now() - make_interval(mins => (seed.h(v, 154) * 525600)::int)
  FROM seed.params p, generate_series(1, (SELECT n_cand / 5 FROM seed.params)) v;

INSERT INTO profile.referral (referrer_app_user_id, referred_candidate_profile_id, referred_email, referral_status_code, referred_at,
                              created_at, updated_at)
SELECT p.u_cand + 1 + floor(seed.h(v, 155) * p.n_cand)::bigint,
       CASE WHEN v % 2 = 0 THEN 1 + floor(seed.h(v, 156) * p.n_cand)::bigint END,
       CASE WHEN v % 2 = 1 THEN 'invitee' || v || '@mail.example' END,
       (ARRAY['invited','registered','applied','hired','expired'])[1 + v % 5],
       now() - make_interval(days => (seed.h(v, 157) * 300)::int), now(), now()
  FROM seed.params p, generate_series(1, (SELECT n_cand / 20 FROM seed.params)) v;

SELECT count(*) AS profiles, count(*) FILTER (WHERE legacy_source_id IS NOT NULL) AS legacy FROM profile.candidate_profile \gset
SELECT count(*) AS dup_candidates FROM seed.cand WHERE is_dup \gset
\echo profiles=:profiles legacy=:legacy near_duplicates=:dup_candidates
