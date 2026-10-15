-- M6 gate: Phase 1 keys and constraints (B20-B23). Every rule is proved by a rejected statement that names its
-- constraint or trigger; the positive test walks one application through the whole pipeline.
-- Numbered tests 1-9 are the Milestone Plan's list; the rest cover the other M6 rules.

DO $test$
DECLARE
  v_recruiter   bigint;
  v_cand_user   bigint;
  v_cand2_user  bigint;
  v_org         bigint;
  v_role        bigint;
  v_profile     bigint;
  v_profile2    bigint;
  v_job         bigint;
  v_job2        bigint;
  v_app         bigint;
  v_app2        bigint;
  v_offer       bigint;
  v_history     text;
  -- column list + fixed values for job_requirement inserts used by the negative tests
  v_job_cols    text := 'organisation_id, posted_by_app_user_id, job_title, description, job_category_code, '
                     || 'employment_type_code, work_type_code, job_role_id';
  v_job_vals    text;
BEGIN
  -- ---------------- fixtures ----------------
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'recruiter@acme.example') RETURNING id INTO v_recruiter;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'priya@example.com') RETURNING id INTO v_cand_user;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'arun@example.com') RETURNING id INTO v_cand2_user;
  INSERT INTO org.organisation (organisation_name, organisation_status_code) VALUES ('Acme Staffing', 'active') RETURNING id INTO v_org;
  SELECT id INTO v_role FROM ref.job_role WHERE role_name = 'Backend Developer';
  v_job_vals := format('%s, %s, %L, %L, %L, %L, %L, %s', v_org, v_recruiter, 'Backend Developer',
                       'Build APIs on PostgreSQL.', 'permanent', 'permanent', 'hybrid', v_role);

  PERFORM set_config('app.current_user_id', v_cand_user::text, true);
  INSERT INTO profile.candidate_profile (app_user_id, full_name, total_experience_months,
                                         expected_salary_disclosure_code, expected_salary_amount, currency_code, pay_period_code)
  VALUES (v_cand_user, 'Priya Raman', 36, 'disclosed', 1500000, 'INR', 'annual') RETURNING id INTO v_profile;
  INSERT INTO profile.candidate_contact (candidate_profile_id, contact_type_code, email, is_primary)
  VALUES (v_profile, 'email', 'priya.raman@example.com', true);
  INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, field_of_study_id, institution_id,
                                           start_date, end_date, score_pct, is_highest)
  SELECT v_profile, q.id, f.id, i.id, DATE '2016-07-01', DATE '2020-05-31', 82.50, true
    FROM ref.qualification q, ref.field_of_study f, ref.institution i
   WHERE q.short_name = 'B.Tech' AND f.field_name = 'Computer Science' AND i.institution_name = 'Anna University';
  INSERT INTO profile.candidate_work_experience (candidate_profile_id, employer_name, designation, employment_type_code,
                                                 start_date, is_current)
  VALUES (v_profile, 'Zoho Corporation', 'Software Engineer', 'permanent', DATE '2020-07-01', true);
  INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id, proficiency_level_code, experience_months)
  SELECT v_profile, id, 'advanced', 36 FROM ref.skill WHERE skill_name IN ('Java', 'PostgreSQL');

  PERFORM set_config('app.current_user_id', v_cand2_user::text, true);
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_cand2_user, 'அருண் குமார்') RETURNING id INTO v_profile2;

  PERFORM set_config('app.current_user_id', v_recruiter::text, true);
  EXECUTE format('INSERT INTO job.job_requirement (%s, job_requirement_status_code, publish_state_code, published_at, '
                 || 'salary_disclosure_code, salary_min, salary_max, currency_code, pay_period_code, '
                 || 'experience_min_months, experience_max_months) VALUES (%s, %L, %L, now(), %L, 1200000, 1800000, %L, %L, 24, 60) RETURNING id',
                 v_job_cols, v_job_vals, 'open', 'published', 'disclosed', 'INR', 'annual') INTO v_job;
  EXECUTE format('INSERT INTO job.job_requirement (%s, job_requirement_status_code, publish_state_code, published_at) '
                 || 'VALUES (%s, %L, %L, now()) RETURNING id', v_job_cols, v_job_vals, 'open', 'published') INTO v_job2;

  PERFORM set_config('app.current_user_id', v_cand_user::text, true);
  INSERT INTO job.application (job_requirement_id, candidate_profile_id) VALUES (v_job, v_profile) RETURNING id INTO v_app;
  PERFORM set_config('app.current_user_id', v_cand2_user::text, true);
  INSERT INTO job.application (job_requirement_id, candidate_profile_id) VALUES (v_job, v_profile2) RETURNING id INTO v_app2;
  PERFORM set_config('app.current_user_id', v_recruiter::text, true);

  -- ---------------- partitioning (D5) ----------------
  PERFORM qa.assert_equals('job.application is hash-partitioned on candidate_profile_id',
    (SELECT pg_get_partkeydef('job.application'::regclass)), 'HASH (candidate_profile_id)');
  PERFORM qa.assert_equals('32 hash partitions',
    (SELECT count(*) FROM pg_inherits WHERE inhparent = 'job.application'::regclass)::int, 32);
  PERFORM qa.assert('each application row landed in exactly one partition and the parent sees both',
    (SELECT count(*) FROM job.application) = 2
    AND (SELECT count(DISTINCT tableoid) FROM job.application) BETWEEN 1 AND 2);

  -- ---------------- Milestone Plan tests 1-9 ----------------
  PERFORM qa.expect_error('1 salary_min 90000 > salary_max 50000',
    format('INSERT INTO job.job_requirement (%s, salary_disclosure_code, salary_min, salary_max, currency_code, pay_period_code) '
           || 'VALUES (%s, %L, 90000, 50000, %L, %L)', v_job_cols, v_job_vals, 'disclosed', 'INR', 'annual'),
    'ck_job_requirement_salary_range');
  PERFORM qa.expect_error('2 not_disclosed salary stored as 0 (sentinel)',
    format('INSERT INTO job.job_requirement (%s, salary_disclosure_code, salary_min) VALUES (%s, %L, 0)',
           v_job_cols, v_job_vals, 'not_disclosed'),
    'ck_job_requirement_salary_disclosure');
  PERFORM qa.expect_error('3 education ends before it starts',
    format('INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, institution_name, start_date, end_date) '
           || 'SELECT %s, id, %L, DATE %L, DATE %L FROM ref.qualification WHERE short_name = %L',
           v_profile, 'Some College', '2024-06-01', '2023-05-01', 'MBA'),
    'ck_candidate_education_date_range');
  PERFORM qa.expect_error('4 duplicate application for the same candidate and job',
    format('INSERT INTO job.application (job_requirement_id, candidate_profile_id) VALUES (%s, %s)', v_job, v_profile),
    'uq_application_candidate_profile_id_job_requirement_id');
  PERFORM qa.expect_error('5 status applied -> joined skips the pipeline',
    format('UPDATE job.application SET application_status_code = %L WHERE id = %s', 'joined', v_app),
    'trg_application_status_transition');
  PERFORM qa.expect_error('6a UPDATE of a status-history row',
    format('UPDATE job.application_status_history SET change_reason = %L WHERE application_id = %s', 'edited', v_app),
    'forbid_update_delete');
  PERFORM qa.expect_error('6b DELETE of a status-history row',
    format('DELETE FROM job.application_status_history WHERE application_id = %s', v_app),
    'forbid_update_delete');
  PERFORM qa.expect_error('7a free-text status on an application',
    format('INSERT INTO job.application (job_requirement_id, candidate_profile_id, application_status_code, application_source_code) '
           || 'VALUES (%s, %s, %L, %L)', v_job2, v_profile2, 'hired', 'imported'),
    'fk_application_application_status_code');
  PERFORM qa.expect_error('7b free-text status in the history',
    format('INSERT INTO job.application_status_history (application_id, candidate_profile_id, to_application_status_code) VALUES (%s, %s, %L)', v_app, v_profile, 'hired'),
    'fk_application_status_history_to_application_status_code');
  PERFORM qa.expect_error('8a contact email in a different case cannot even be stored (lowercase domain)',
    format('INSERT INTO profile.candidate_contact (candidate_profile_id, contact_type_code, email) VALUES (%s, %L, %L)',
           v_profile2, 'email', 'Priya.Raman@Example.com'),
    'ck_d_email_lowercase');
  PERFORM qa.expect_error('8b duplicate contact email on another profile',
    format('INSERT INTO profile.candidate_contact (candidate_profile_id, contact_type_code, email) VALUES (%s, %L, %L)',
           v_profile2, 'email', 'priya.raman@example.com'),
    'uq_candidate_contact_email');
  PERFORM qa.expect_error('9 delete a job requirement that has applications',
    format('DELETE FROM job.job_requirement WHERE id = %s', v_job),
    'fk_application_job_requirement_id');

  -- ---------------- other M6 rules ----------------
  EXECUTE format('UPDATE job.job_requirement SET job_requirement_status_code = %L WHERE id = %s', 'on_hold', v_job2);
  PERFORM qa.expect_error('apply to an on-hold job',
    format('INSERT INTO job.application (job_requirement_id, candidate_profile_id) VALUES (%s, %s)', v_job2, v_profile2),
    'trg_application_status_transition');
  EXECUTE format('UPDATE job.job_requirement SET job_requirement_status_code = %L WHERE id = %s', 'open', v_job2);
  PERFORM qa.expect_error('a new application must start as applied',
    format('INSERT INTO job.application (job_requirement_id, candidate_profile_id, application_status_code) VALUES (%s, %s, %L)',
           v_job2, v_profile2, 'shortlisted'),
    'trg_application_status_transition');
  PERFORM qa.expect_error('rejection without a reason',
    format('UPDATE job.application SET application_status_code = %L WHERE id = %s', 'rejected', v_app2),
    'ck_application_rejection_reason');
  PERFORM qa.expect_error('experience minimum above maximum',
    format('INSERT INTO job.job_requirement (%s, experience_min_months, experience_max_months) VALUES (%s, 60, 24)',
           v_job_cols, v_job_vals),
    'ck_job_requirement_experience_range');
  PERFORM qa.expect_error('open to consultants without a fee',
    format('INSERT INTO job.job_requirement (%s, is_open_to_consultant) VALUES (%s, true)', v_job_cols, v_job_vals),
    'ck_job_requirement_consultant_fee');
  PERFORM qa.expect_error('salary in an unknown currency',
    format('INSERT INTO job.job_requirement (%s, salary_disclosure_code, salary_min, currency_code, pay_period_code) '
           || 'VALUES (%s, %L, 100, %L, %L)', v_job_cols, v_job_vals, 'disclosed', 'XYZ', 'annual'),
    'fk_job_requirement_currency_code');
  PERFORM qa.expect_error('second profile for the same login',
    format('INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (%s, %L)', v_cand_user, 'Priya R'),
    'uq_candidate_profile_app_user_id');
  PERFORM qa.expect_error('profile salary disclosed without currency',
    format('UPDATE profile.candidate_profile SET currency_code = NULL, pay_period_code = NULL WHERE id = %s', v_profile),
    'ck_candidate_profile_salary_currency');
  PERFORM qa.expect_error('email contact carrying a phone number',
    format('INSERT INTO profile.candidate_contact (candidate_profile_id, contact_type_code, email, phone) VALUES (%s, %L, %L, %L)',
           v_profile2, 'email', 'arun@example.com', '+919840012345'),
    'ck_candidate_contact_value_by_type');
  PERFORM qa.expect_error('work experience with neither a registered employer nor a name',
    format('INSERT INTO profile.candidate_work_experience (candidate_profile_id, designation, employment_type_code, start_date, is_current) '
           || 'VALUES (%s, %L, %L, DATE %L, true)', v_profile2, 'Welder', 'contract', '2022-01-01'),
    'ck_candidate_work_experience_employer');
  PERFORM qa.expect_error('two highest qualifications',
    format('INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, institution_name, start_date, is_highest) '
           || 'SELECT %s, id, %L, DATE %L, true FROM ref.qualification WHERE short_name = %L', v_profile, 'IIM', '2021-06-01', 'MBA'),
    'uq_candidate_education_one_highest');
  PERFORM qa.expect_error('interview that ends before it starts',
    format('INSERT INTO job.interview (application_id, candidate_profile_id, round_number, interview_mode_code, scheduled_start, scheduled_end, meeting_url) '
           || 'VALUES (%s, %s, 9, %L, now(), now() - interval %L, %L)', v_app, v_profile, 'video', '1 hour', 'https://meet.example.com/x'),
    'ck_interview_schedule');
  PERFORM qa.expect_error('opening filled by an application to another job',
    format('INSERT INTO job.job_position (job_requirement_id, position_number, filled_by_application_id, filled_by_candidate_profile_id, filled_on) '
           || 'VALUES (%s, 1, %s, %s, current_date)', v_job2, v_app, v_profile),
    'fk_job_position_filled_by_application');
  PERFORM qa.expect_error('history row whose candidate does not match its application (composite FK)',
    format('INSERT INTO job.application_status_history (application_id, candidate_profile_id, to_application_status_code) VALUES (%s, %s, %L)',
           v_app, v_profile2, 'applied'),
    'fk_application_status_history_application');

  -- review fix R1: an application cannot carry someone else's resume
  PERFORM set_config('app.current_user_id', v_cand_user::text, true);
  INSERT INTO profile.resume_version (candidate_profile_id, version_number, body, body_language_id)
  SELECT v_profile, 1, 'Priya Raman - Backend Developer', id FROM ref.language WHERE code = 'en';
  PERFORM set_config('app.current_user_id', v_recruiter::text, true);
  PERFORM qa.expect_error('application attaching another candidate''s resume',
    format('UPDATE job.application SET resume_version_id = (SELECT id FROM profile.resume_version WHERE candidate_profile_id = %s) WHERE id = %s',
           v_profile, v_app2),
    'fk_application_resume_version_owner');
  PERFORM qa.expect_ok('application attaching the applicant''s own resume',
    format('UPDATE job.application SET resume_version_id = (SELECT id FROM profile.resume_version WHERE candidate_profile_id = %s) WHERE id = %s',
           v_profile, v_app));

  -- ---------------- positive pipeline: applied -> shortlisted -> interviewed -> offered -> joined ----------------
  PERFORM qa.expect_ok('shortlist',
    format('UPDATE job.application SET application_status_code = %L WHERE id = %s', 'shortlisted', v_app));
  INSERT INTO job.interview (application_id, candidate_profile_id, round_number, interview_mode_code, interview_status_code, interview_outcome_code,
                             interviewer_app_user_id, scheduled_start, scheduled_end, meeting_url)
  VALUES (v_app, v_profile, 1, 'video', 'completed', 'passed', v_recruiter, now(), now() + interval '45 minutes', 'https://meet.example.com/abc');
  PERFORM qa.expect_ok('interviewed',
    format('UPDATE job.application SET application_status_code = %L WHERE id = %s', 'interviewed', v_app));
  INSERT INTO job.offer (application_id, candidate_profile_id, ctc_amount, ctc_currency_code, ctc_pay_period_code, offered_on, proposed_joining_date)
  VALUES (v_app, v_profile, 1650000, 'INR', 'annual', current_date, current_date + 30) RETURNING id INTO v_offer;
  PERFORM qa.expect_ok('offered',
    format('UPDATE job.application SET application_status_code = %L WHERE id = %s', 'offered', v_app));
  PERFORM qa.expect_error('joining against an offer made on another application',
    format('INSERT INTO job.joining (application_id, candidate_profile_id, offer_id, expected_joining_date) VALUES (%s, %s, %s, current_date)', v_app2, v_profile2, v_offer),
    'fk_joining_offer_id_application_id');
  UPDATE job.offer SET offer_status_code = 'accepted', responded_at = now() WHERE id = v_offer;
  INSERT INTO job.joining (application_id, candidate_profile_id, offer_id, joining_status_code, expected_joining_date, actual_joining_date)
  VALUES (v_app, v_profile, v_offer, 'joined', current_date + 30, current_date + 30);
  PERFORM qa.expect_ok('joined',
    format('UPDATE job.application SET application_status_code = %L WHERE id = %s', 'joined', v_app));
  PERFORM qa.expect_ok('opening filled by the joined application',
    format('INSERT INTO job.job_position (job_requirement_id, position_number, filled_by_application_id, filled_by_candidate_profile_id, filled_on) '
           || 'VALUES (%s, 1, %s, %s, current_date)', v_job, v_app, v_profile));

  SELECT string_agg(coalesce(from_application_status_code, '-') || '>' || to_application_status_code, ' ' ORDER BY id)
    INTO v_history FROM job.application_status_history WHERE application_id = v_app;
  PERFORM qa.assert_equals('5 history rows trace the full pipeline', v_history,
    '->applied applied>shortlisted shortlisted>interviewed interviewed>offered offered>joined');
  PERFORM qa.assert_equals('history actor is the recruiter who moved the application',
    (SELECT count(*) FROM job.application_status_history WHERE application_id = v_app AND created_by = v_recruiter)::int, 4);
  PERFORM qa.expect_error('joined is terminal (joined -> rejected)',
    format('UPDATE job.application SET application_status_code = %L, rejection_reason_code = %L WHERE id = %s',
           'rejected', 'other', v_app),
    'trg_application_status_transition');
  PERFORM qa.expect_ok('rejection with a reason',
    format('UPDATE job.application SET application_status_code = %L, rejection_reason_code = %L WHERE id = %s',
           'rejected', 'skills_mismatch', v_app2));
  UPDATE job.job_requirement SET deleted_at = now() WHERE id = v_job2;
  PERFORM qa.assert('soft-deleted job leaves the default view but the row remains',
    NOT EXISTS (SELECT 1 FROM job.v_job_requirement WHERE id = v_job2)
    AND EXISTS (SELECT 1 FROM job.job_requirement WHERE id = v_job2));
  PERFORM qa.expect_error('apply to a soft-deleted job',
    format('INSERT INTO job.application (job_requirement_id, candidate_profile_id) VALUES (%s, %s)', v_job2, v_profile2),
    'trg_application_status_transition');
END
$test$;
