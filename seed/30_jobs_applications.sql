-- M19 seed, step 3 (Jobs and Applications): job requirements, positions, questionnaires, applications across the full
-- status pipeline with consistent history, interviews, offers, joinings, searches and shortlists.
\ir _preamble.sql

-- ---------------------------------------------------------------------------------------------------
-- Job requirements (owner organisation skewed towards large employers; posted by a recruiter mapped to that organisation)
INSERT INTO job.job_requirement (id, organisation_id, client_organisation_id, posted_by_app_user_id, job_title, description,
       description_language_id, job_category_code, employment_type_code, work_type_code, job_role_id, industry_id,
       job_requirement_status_code, publish_state_code, salary_disclosure_code, salary_min, salary_max, currency_code, pay_period_code,
       experience_min_months, experience_max_months, notice_period_code, is_open_to_consultant, consultant_fee_pct, published_at,
       application_deadline, legacy_source_system, legacy_source_id, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT j.id, o.org, CASE WHEN seed.h(j.id, 201) < 0.20 THEN 1 + (p.n_hiring + (j.id % GREATEST(1, p.n_org - p.n_hiring)))::bigint END,
       p.u_rec + o.org + p.n_hiring * (j.id % 2),
       r.role_names[o.role_idx] || CASE WHEN j.id % 3 = 0 THEN ' (Contract)' ELSE '' END,
       'We are hiring a ' || r.role_names[o.role_idx] || '. Responsibilities, requirements and benefits are listed in the full posting. Reference ' || j.id || '.',
       CASE WHEN seed.h(j.id, 202) < 0.85 THEN r.lang_en END,
       (ARRAY['general_staffing','professional_staffing','permanent','apprentice','campus','consultant_marketplace','managed_remote'])
         [seed.wpick(j.id, 203, ARRAY[0.15,0.35,0.70,0.78,0.88,0.95,1.0])],
       (ARRAY['permanent','contract','temporary','apprentice','internship'])[seed.wpick(j.id, 204, ARRAY[0.55,0.80,0.88,0.94,1.0])],
       (ARRAY['onsite','remote','hybrid'])[seed.wpick(j.id, 205, ARRAY[0.50,0.70,1.0])],
       r.roles[o.role_idx], r.industries[1 + floor(seed.h(j.id, 206) * array_length(r.industries, 1))::int],
       st.status, st.publish,
       CASE WHEN sal.disclosed THEN 'disclosed' WHEN seed.h(j.id, 207) < 0.05 THEN 'not_applicable' ELSE 'not_disclosed' END,
       CASE WHEN sal.disclosed THEN sal.smin END, CASE WHEN sal.disclosed THEN round(sal.smin * (1.2 + seed.h(j.id, 208) * 0.6), -3) END,
       CASE WHEN sal.disclosed THEN 'INR' END, CASE WHEN sal.disclosed THEN 'annual' END,
       CASE WHEN seed.h(j.id, 209) < 0.90 THEN exps.emin END, CASE WHEN seed.h(j.id, 209) < 0.90 THEN exps.emin + 12 + (seed.h(j.id, 210) * 48)::int END,
       CASE WHEN seed.h(j.id, 211) < 0.30 THEN (ARRAY['immediate','days_30','days_60','days_90'])[1 + j.id % 4] END,
       cons.open, CASE WHEN cons.open THEN 8.33 END,
       CASE WHEN st.publish <> 'unpublished' THEN created.at + interval '1 day' END,
       CASE WHEN st.status = 'open' THEN current_date + (30 + j.id % 60)::int END,
       CASE WHEN seed.h(j.id, 212) < 0.05 THEN 'legacy_monster_export' END,
       CASE WHEN seed.h(j.id, 212) < 0.05 THEN 'LM-' || j.id END,
       created.at, created.at + interval '1 day'
  FROM generate_series(1, (SELECT n_job FROM seed.params)) j(id)
  CROSS JOIN seed.params p CROSS JOIN seed.refs r
  CROSS JOIN LATERAL (SELECT 1 + floor(power(seed.h(j.id, 200), 1.5) * p.n_hiring)::bigint AS org,
                             1 + floor(seed.h(j.id, 213) * array_length(r.roles, 1))::int AS role_idx) o
  CROSS JOIN LATERAL (SELECT now() - make_interval(days => 62 + (seed.h(j.id, 214) * 478)::int) AS at) created
  CROSS JOIN LATERAL (SELECT (seed.h(j.id, 215) < 0.55) AS disclosed, round(300000 + seed.h(j.id, 216) * 2200000, -3) AS smin) sal
  CROSS JOIN LATERAL (SELECT (seed.h(j.id, 217) * 60)::int AS emin) exps
  CROSS JOIN LATERAL (SELECT seed.h(j.id, 218) < 0.20 AS open) cons
  CROSS JOIN LATERAL (SELECT (ARRAY['open','closed','filled','draft','on_hold','cancelled'])[seed.wpick(j.id, 219, ARRAY[0.60,0.82,0.90,0.94,0.97,1.0])] AS status) s0
  CROSS JOIN LATERAL (SELECT s0.status AS status,
                             CASE s0.status WHEN 'open' THEN 'published' WHEN 'closed' THEN 'expired' WHEN 'filled' THEN 'expired'
                                            WHEN 'cancelled' THEN 'withdrawn' ELSE 'unpublished' END AS publish) st;

-- positions: 1-3 openings per job
INSERT INTO job.job_position (job_requirement_id, position_number, created_at, updated_at)
SELECT j.id, k, j.created_at, j.created_at
  FROM job.job_requirement j CROSS JOIN LATERAL generate_series(1, 1 + (seed.h(j.id, 220) * 3)::int) k;

INSERT INTO job.job_requirement_skill (job_requirement_id, skill_id, is_mandatory, min_proficiency_level_code, created_at, updated_at)
SELECT j.id, r.skills[1 + floor(power(seed.h(j.id * 4 + k, 221), 1.3) * array_length(r.skills, 1))::int], k <= 2,
       CASE WHEN k = 1 THEN 'intermediate' END, j.created_at, j.created_at
  FROM job.job_requirement j CROSS JOIN seed.refs r CROSS JOIN generate_series(1, 3) k
ON CONFLICT DO NOTHING;

INSERT INTO job.job_requirement_location (job_requirement_id, city_id, created_at, updated_at)
SELECT j.id, r.cities[1 + floor(power(seed.h(j.id * 2 + k, 222), 1.7) * array_length(r.cities, 1))::int], j.created_at, j.created_at
  FROM job.job_requirement j CROSS JOIN seed.refs r CROSS JOIN generate_series(1, 2) k WHERE k = 1 OR seed.h(j.id, 223) < 0.30
ON CONFLICT DO NOTHING;

INSERT INTO job.job_requirement_qualification (job_requirement_id, qualification_id, is_mandatory, created_at, updated_at)
SELECT j.id, r.quals[1 + floor(seed.h(j.id, 224) * array_length(r.quals, 1))::int], seed.h(j.id, 225) < 0.7, j.created_at, j.created_at
  FROM job.job_requirement j CROSS JOIN seed.refs r;

-- questionnaires: one per organisation up to half of the hiring organisations, three questions each
INSERT INTO job.questionnaire (id, organisation_id, questionnaire_title, language_id)
OVERRIDING SYSTEM VALUE
SELECT q, q, 'Screening questions', (SELECT lang_en FROM seed.refs) FROM generate_series(1, (SELECT greatest(1, n_hiring / 2) FROM seed.params)) q;
INSERT INTO job.questionnaire_question (questionnaire_id, question_order, question_text, question_type_code, is_mandatory, is_knockout)
SELECT q.id, k, (ARRAY['Are you willing to relocate?','How many years of relevant experience do you have?','Which notice period applies to you?'])[k],
       (ARRAY['yes_no','numeric','single_choice'])[k], true, k = 1
  FROM job.questionnaire q CROSS JOIN generate_series(1, 3) k;
INSERT INTO job.question_option (questionnaire_question_id, option_order, option_text, is_knockout_answer)
SELECT qq.id, o, CASE qq.question_type_code WHEN 'yes_no' THEN (ARRAY['Yes','No'])[o]
                                            ELSE (ARRAY['Immediate','30 days','60 days','90 days'])[o] END,
       qq.question_type_code = 'yes_no' AND o = 2
  FROM job.questionnaire_question qq
  CROSS JOIN LATERAL generate_series(1, CASE qq.question_type_code WHEN 'yes_no' THEN 2 WHEN 'single_choice' THEN 4 ELSE 0 END) o;
INSERT INTO job.job_requirement_questionnaire (job_requirement_id, questionnaire_id, created_at, updated_at)
SELECT j.id, j.organisation_id, j.created_at, j.created_at
  FROM job.job_requirement j WHERE j.organisation_id <= (SELECT max(id) FROM job.questionnaire) AND seed.h(j.id, 226) < 0.35;

-- ---------------------------------------------------------------------------------------------------
-- Applications. A plan table is built first (and de-duplicated on candidate+job so the unique key is never violated).
CREATE TABLE seed.job_pool AS
SELECT row_number() OVER (ORDER BY id) AS rn, id, organisation_id AS org, created_at,
       least(created_at + interval '1 day', now() - interval '60 days') AS opens_at
  FROM job.job_requirement WHERE job_requirement_status_code <> 'draft';
ALTER TABLE seed.job_pool ADD PRIMARY KEY (rn);
CREATE UNIQUE INDEX ON seed.job_pool (id);

CREATE UNLOGGED TABLE seed.app_plan AS
WITH raw AS (
  SELECT n,
         1 + ((n - 1) % p.n_cand) AS cand,
         1 + floor(power(seed.h(n, 230), 2.5) * (SELECT count(*) FROM seed.job_pool))::bigint AS job_rn,
         seed.h(n, 231) AS r_stage, seed.h(n, 232) AS r_exit
    FROM seed.params p, generate_series(1, (SELECT ceil(n_app * 1.04)::bigint FROM seed.params)) n
), j AS (
  SELECT raw.*, jp.id AS job, jp.org, jp.opens_at
    FROM raw JOIN seed.job_pool jp ON jp.rn = raw.job_rn
), ranked AS (
  SELECT j.*, row_number() OVER (PARTITION BY cand, job ORDER BY n) AS dup_rank FROM j
), kept AS (
  SELECT *, row_number() OVER (ORDER BY n) AS id FROM ranked WHERE dup_rank = 1
)
SELECT id, cand, job, org,
       -- furthest stage reached: 1 applied, 2 shortlisted (30%), 3 interviewed (12%), 4 offered (4%), 5 joined (3%)
       CASE WHEN r_stage < 0.03 THEN 5 WHEN r_stage < 0.04 THEN 4 WHEN r_stage < 0.12 THEN 3 WHEN r_stage < 0.30 THEN 2 ELSE 1 END AS stage,
       -- how the pipeline ended for this application (joined is always the end of stage 5)
       CASE WHEN r_stage < 0.03 THEN 'stay' WHEN r_exit < 0.45 THEN 'rejected' WHEN r_exit < 0.50 THEN 'withdrawn' ELSE 'stay' END AS ending,
       opens_at + (seed.h(id, 233) * GREATEST(extract(epoch FROM (now() - interval '30 days' - opens_at)), 3600)) * interval '1 second' AS applied_at,
       seed.h(id, 234) AS r_src
  FROM kept WHERE id <= (SELECT n_app FROM seed.params);
ALTER TABLE seed.app_plan ADD PRIMARY KEY (id);
SELECT count(*) AS planned FROM seed.app_plan \gset
\echo application plan rows: :planned

INSERT INTO job.application (id, job_requirement_id, candidate_profile_id, application_status_code, application_source_code,
                             rejection_reason_code, resume_version_id, applied_at, status_changed_at, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT ap.id, ap.job, ap.cand, f.final,
       (ARRAY['direct','sourced','referral','campus','consultant','imported'])[seed.wpick(ap.id, 235, ARRAY[0.70,0.80,0.85,0.90,0.95,1.0])],
       CASE WHEN f.final = 'rejected'
            THEN (ARRAY['skills_mismatch','experience_mismatch','salary_mismatch','location_mismatch','failed_interview','no_show','position_filled','other'])[1 + (ap.id % 8)] END,
       CASE WHEN rv.id IS NOT NULL AND seed.h(ap.id, 236) < 0.60 THEN rv.id END,
       ap.applied_at,
       ap.applied_at + make_interval(days => f.steps * 3),
       ap.applied_at, ap.applied_at + make_interval(days => f.steps * 3)
  FROM seed.app_plan ap
  CROSS JOIN LATERAL (SELECT CASE WHEN ap.stage = 5 THEN 'joined'
                                  WHEN ap.ending = 'stay' THEN (ARRAY['applied','shortlisted','interviewed','offered'])[ap.stage]
                                  ELSE ap.ending END AS final,
                             ap.stage - 1 + CASE WHEN ap.ending <> 'stay' AND ap.stage < 5 THEN 1 ELSE 0 END AS steps) f
  LEFT JOIN profile.resume_version rv ON rv.candidate_profile_id = ap.cand;

-- status history: one row per step of the chain (legal transitions only), first row has no previous status
INSERT INTO job.application_status_history (application_id, candidate_profile_id, from_application_status_code, to_application_status_code,
                                            changed_at, created_at)
SELECT ap.id, ap.cand,
       CASE WHEN k = 1 THEN NULL ELSE (ARRAY['applied','shortlisted','interviewed','offered','joined'])[k - 1] END,
       CASE WHEN k <= ap.stage THEN (ARRAY['applied','shortlisted','interviewed','offered','joined'])[k] ELSE ap.ending END,
       ap.applied_at + make_interval(days => (k - 1) * 3), ap.applied_at + make_interval(days => (k - 1) * 3)
  FROM seed.app_plan ap
  CROSS JOIN LATERAL generate_series(1, ap.stage + CASE WHEN ap.ending <> 'stay' AND ap.stage < 5 THEN 1 ELSE 0 END) k;

-- interviews (stage 3+), offers (stage 4+), joinings (stage 5); interviewer is a recruiter of the job's organisation
INSERT INTO job.interview (application_id, candidate_profile_id, round_number, interview_mode_code, interview_status_code, interview_outcome_code,
                           interviewer_app_user_id, scheduled_start, scheduled_end, venue, meeting_url, created_at, updated_at)
SELECT ap.id, ap.cand, 1, m.mode, 'completed',
       CASE WHEN ap.stage >= 4 OR (ap.ending = 'stay') THEN 'passed' ELSE 'failed' END,
       p.u_rec + ap.org + p.n_hiring * (ap.id % 2),
       ap.applied_at + interval '6 days', ap.applied_at + interval '6 days 45 minutes',
       CASE WHEN m.mode = 'in_person' THEN 'Head office, floor ' || (1 + ap.id % 9) END,
       CASE WHEN m.mode = 'video' THEN 'https://meet.example/' || ap.id END,
       ap.applied_at + interval '6 days', ap.applied_at + interval '6 days 45 minutes'
  FROM seed.app_plan ap CROSS JOIN seed.params p
  CROSS JOIN LATERAL (SELECT (ARRAY['video','in_person','phone'])[1 + ap.id % 3] AS mode) m
 WHERE ap.stage >= 3;

INSERT INTO job.offer (application_id, candidate_profile_id, offer_status_code, ctc_amount, ctc_currency_code, ctc_pay_period_code,
                       offered_on, proposed_joining_date, valid_until, responded_at, created_at, updated_at)
SELECT ap.id, ap.cand,
       CASE WHEN ap.stage = 5 THEN 'accepted' WHEN ap.ending = 'rejected' THEN 'declined' WHEN ap.ending = 'withdrawn' THEN 'withdrawn' ELSE 'extended' END,
       round(400000 + seed.h(ap.id, 240) * 2600000, -3), 'INR', 'annual',
       (ap.applied_at + interval '9 days')::date, (ap.applied_at + interval '45 days')::date, (ap.applied_at + interval '23 days')::date,
       CASE WHEN ap.stage = 5 OR ap.ending = 'rejected' THEN ap.applied_at + interval '12 days' END,
       ap.applied_at + interval '9 days', ap.applied_at + interval '12 days'
  FROM seed.app_plan ap WHERE ap.stage >= 4;

INSERT INTO job.joining (application_id, candidate_profile_id, offer_id, joining_status_code, expected_joining_date, actual_joining_date,
                         created_at, updated_at)
SELECT ap.id, ap.cand, o.id, 'joined', o.proposed_joining_date, o.proposed_joining_date, o.created_at, o.created_at
  FROM seed.app_plan ap JOIN job.offer o ON o.application_id = ap.id WHERE ap.stage = 5;

-- filled positions: the k-th joined application of a job fills position k
UPDATE job.job_position pos
   SET filled_by_application_id = j.application_id, filled_by_candidate_profile_id = j.candidate_profile_id, filled_on = j.filled_on
  FROM (SELECT a.job_requirement_id, a.id AS application_id, a.candidate_profile_id,
               jn.actual_joining_date AS filled_on,
               row_number() OVER (PARTITION BY a.job_requirement_id ORDER BY a.id) AS rn
          FROM job.application a JOIN job.joining jn ON jn.application_id = a.id) j
 WHERE pos.job_requirement_id = j.job_requirement_id AND pos.position_number = j.rn;

-- screening answers for a 10% sample of applications on jobs with a questionnaire
INSERT INTO job.application_answer (application_id, candidate_profile_id, questionnaire_question_id, question_option_id, answer_number, created_at, updated_at)
SELECT a.id, a.candidate_profile_id, qq.id,
       CASE WHEN qq.question_type_code <> 'numeric'
            THEN (SELECT id FROM job.question_option WHERE questionnaire_question_id = qq.id AND option_order = 1) END,
       CASE WHEN qq.question_type_code = 'numeric' THEN (a.id % 15)::numeric END, a.applied_at, a.applied_at
  FROM job.application a
  JOIN job.job_requirement_questionnaire jq ON jq.job_requirement_id = a.job_requirement_id
  JOIN job.questionnaire_question qq ON qq.questionnaire_id = jq.questionnaire_id AND qq.question_order <= 3
 WHERE a.id % 10 = 0;

-- saved searches, search history (candidates and guests), shortlists
INSERT INTO job.saved_search (candidate_profile_id, search_name, search_criteria, created_at, updated_at)
SELECT 1 + (v % p.n_cand), 'Search ' || (v / p.n_cand + 1),
       jsonb_build_object('role', (SELECT role_names[1 + (v % array_length(role_names, 1))] FROM seed.refs),
                          'city_id', (SELECT cities[1 + (v % array_length(cities, 1))] FROM seed.refs)),
       now() - make_interval(days => (seed.h(v, 250) * 300)::int), now()
  FROM seed.params p, generate_series(1, (SELECT n_cand / 5 FROM seed.params)) v;

INSERT INTO job.job_search_event (candidate_profile_id, session_token, search_query, search_filters, result_count, searched_at, created_at)
SELECT CASE WHEN v % 2 = 0 THEN 1 + floor(seed.h(v, 251) * p.n_cand)::bigint END,
       CASE WHEN v % 2 = 1 THEN 'guest-' || md5(v::text) END,
       (ARRAY['data analyst','welder','sales executive','accountant','java developer','forklift operator'])[1 + v % 6],
       jsonb_build_object('work_type', (ARRAY['onsite','remote','hybrid'])[1 + v % 3]),
       (seed.h(v, 252) * 2000)::int, now() - make_interval(mins => (seed.h(v, 253) * 525600)::int), now()
  FROM seed.params p, generate_series(1, (SELECT n_cand FROM seed.params)) v;

INSERT INTO job.shortlist (organisation_id, owner_app_user_id, job_requirement_id, shortlist_name, created_at, updated_at)
SELECT j.organisation_id, j.posted_by_app_user_id, j.id, 'Shortlist for job ' || j.id, j.created_at, j.created_at
  FROM job.job_requirement j WHERE j.id % 5 = 0 AND j.job_requirement_status_code <> 'draft';
INSERT INTO job.shortlist_entry (shortlist_id, candidate_profile_id, entry_note, created_at, updated_at)
SELECT s.id, 1 + ((s.job_requirement_id * 17 + k * 131) % p.n_cand), CASE WHEN k = 1 THEN 'Strong match' END, s.created_at, s.created_at
  FROM job.shortlist s CROSS JOIN seed.params p CROSS JOIN generate_series(1, 8) k;

SELECT count(*) AS jobs FROM job.job_requirement \gset
SELECT count(*) AS applications FROM job.application \gset
SELECT count(*) AS history_rows FROM job.application_status_history \gset
\echo jobs=:jobs applications=:applications history=:history_rows
