-- M18 gate, Analytics layer (B58): SCD2 versioning, one pipeline fact for job + gig, idempotent refresh.

DO $test$
DECLARE
  v_org      bigint;
  v_rec      bigint;
  v_cand     bigint;
  v_worker_u bigint;
  v_profile  bigint;
  v_worker   bigint;
  v_role     bigint;
  v_job      bigint;
  v_app      bigint;
  v_gig      bigint;
  v_r1       jsonb;
  v_r2       jsonb;
  v_counts1  text;
  v_counts2  text;
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO org.organisation (organisation_name) VALUES ('Acme') RETURNING id INTO v_org;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'dw.rec@acme.example') RETURNING id INTO v_rec;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'dw.cand@example.com') RETURNING id INTO v_cand;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'dw.worker@example.com') RETURNING id INTO v_worker_u;
  INSERT INTO profile.candidate_profile (app_user_id, full_name, total_experience_months, current_city_id)
  SELECT v_cand, 'Farah', 36, id FROM ref.city WHERE city_name = 'Chennai' RETURNING id INTO v_profile;
  INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, institution_name, start_date, end_date)
  SELECT v_profile, id, 'Anna University', DATE '2016-07-01', DATE '2020-05-31' FROM ref.qualification WHERE short_name = 'B.Tech';
  SELECT id INTO v_role FROM ref.job_role WHERE role_name = 'Data Analyst';
  INSERT INTO job.job_requirement (organisation_id, posted_by_app_user_id, job_title, description, job_category_code, employment_type_code,
                                   work_type_code, job_role_id, job_requirement_status_code, publish_state_code, published_at,
                                   salary_disclosure_code, salary_min, salary_max, currency_code, pay_period_code)
  VALUES (v_org, v_rec, 'Analyst', 'SQL', 'permanent', 'permanent', 'hybrid', v_role, 'open', 'published', now(),
          'disclosed', 800000, 1000000, 'INR', 'annual') RETURNING id INTO v_job;
  INSERT INTO job.application (job_requirement_id, candidate_profile_id) VALUES (v_job, v_profile) RETURNING id INTO v_app;
  UPDATE job.application SET application_status_code = 'shortlisted' WHERE id = v_app;

  INSERT INTO gig.gig_worker_profile (app_user_id, headline) VALUES (v_worker_u, 'Event staff') RETURNING id INTO v_worker;
  INSERT INTO gig.gig_request (requester_app_user_id, requester_organisation_id, gig_title, gig_description, skill_id, window_start, window_end,
                               pricing_model_code, fixed_price_amount, currency_code, gig_request_status_code)
  SELECT v_rec, v_org, 'Expo staff', 'Booth', id, now() + interval '2 days', now() + interval '2 days 4 hours', 'fixed', 4000, 'INR', 'open'
    FROM ref.skill WHERE skill_name = 'Customer Service' RETURNING id INTO v_gig;
  PERFORM set_config('app.current_user_id', v_worker_u::text, true);
  INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id) VALUES (v_gig, v_worker);
  PERFORM set_config('app.current_user_id', '1', true);

  -- first load
  v_r1 := dw.refresh_marts();
  PERFORM qa.assert_equals('one current version per candidate',
    (SELECT count(*) FROM dw.dim_candidate WHERE candidate_profile_id = v_profile AND is_current)::int, 1);
  PERFORM qa.assert_equals('candidate dimension derives band and highest level',
    (SELECT experience_band || '/' || highest_qualification_level FROM dw.dim_candidate WHERE candidate_profile_id = v_profile AND is_current),
    '2-5y/bachelor');
  PERFORM qa.assert_equals('job dimension bands the annualised salary',
    (SELECT salary_band FROM dw.dim_job_requirement WHERE job_requirement_id = v_job AND is_current)::text, '6-12L');
  PERFORM qa.assert_equals('fact holds the job and the gig application (one pipeline view)',
    (SELECT string_agg(source_system, ',' ORDER BY source_system) FROM dw.fact_application
      WHERE (source_system, source_application_id) IN (('job', v_app), ('gig', (SELECT id FROM gig.gig_application WHERE gig_request_id = v_gig)))),
    'gig,job');
  PERFORM qa.assert('funnel flags come from the status history',
    (SELECT reached_shortlisted AND NOT reached_offered FROM dw.fact_application WHERE source_system = 'job' AND source_application_id = v_app));
  PERFORM qa.assert('aggregate equals the fact',
    (SELECT sum(applied_count) FROM dw.agg_daily_funnel) = (SELECT count(*) FROM dw.fact_application));

  -- idempotent: a second run changes nothing
  SELECT format('%s/%s/%s/%s', (SELECT count(*) FROM dw.dim_candidate), (SELECT count(*) FROM dw.dim_job_requirement),
                (SELECT count(*) FROM dw.fact_application), (SELECT sum(applied_count) FROM dw.agg_daily_funnel)) INTO v_counts1;
  v_r2 := dw.refresh_marts();
  SELECT format('%s/%s/%s/%s', (SELECT count(*) FROM dw.dim_candidate), (SELECT count(*) FROM dw.dim_job_requirement),
                (SELECT count(*) FROM dw.fact_application), (SELECT sum(applied_count) FROM dw.agg_daily_funnel)) INTO v_counts2;
  PERFORM qa.assert_equals('refresh run twice gives the same counts', v_counts2, v_counts1);
  PERFORM qa.assert_equals('second run reports zero changed rows', (v_r2 ->> 'rows_changed')::int, 0);

  -- SCD2: a change closes the current version and opens a new one
  UPDATE profile.candidate_profile SET current_city_id = (SELECT id FROM ref.city WHERE city_name = 'Bengaluru') WHERE id = v_profile;
  PERFORM dw.refresh_marts();
  PERFORM qa.assert_equals('the candidate now has two versions', (SELECT count(*) FROM dw.dim_candidate WHERE candidate_profile_id = v_profile)::int, 2);
  PERFORM qa.assert('the old version is closed and the new one is current',
    (SELECT bool_and(CASE WHEN city_name = 'Chennai' THEN NOT is_current AND valid_to IS NOT NULL
                          ELSE is_current AND valid_to IS NULL END)
       FROM dw.dim_candidate WHERE candidate_profile_id = v_profile));
  PERFORM qa.assert_equals('the fact still points at the version valid when the candidate applied',
    (SELECT dc.city_name FROM dw.fact_application f JOIN dw.dim_candidate dc ON dc.id = f.dim_candidate_id
      WHERE f.source_system = 'job' AND f.source_application_id = v_app)::text, 'Chennai');
  PERFORM qa.expect_error('two current versions of one candidate',
    format('UPDATE dw.dim_candidate SET is_current = true, valid_to = NULL WHERE candidate_profile_id = %s', v_profile),
    'uq_dim_candidate_current');
  PERFORM qa.assert('KPI view answers', EXISTS (SELECT 1 FROM dw.v_funnel_by_category WHERE job_category = 'permanent' AND applied >= 1));
  PERFORM qa.assert('application role reads the warehouse but cannot write it',
    has_table_privilege('talentra_app', 'dw.fact_application', 'SELECT')
    AND NOT has_table_privilege('talentra_app', 'dw.fact_application', 'INSERT'));
END
$test$;
