-- M18 gate, shared access layer (docket Section 3): row-level security proved as the application role.
-- Fixtures are created as the owner; the checks run after SET LOCAL ROLE talentra_app with a session actor.

DO $test$
DECLARE
  v_org_a      bigint;
  v_org_b      bigint;
  v_rec_a      bigint;
  v_rec_b      bigint;
  v_consultant bigint;
  v_admin      bigint;
  v_c1         bigint;
  v_c2         bigint;
  v_c3         bigint;
  v_c4         bigint;
  v_p1         bigint;
  v_p2         bigint;
  v_p3         bigint;
  v_role       bigint;
  v_ja1        bigint;
  v_ja2        bigint;
  v_jb1        bigint;
  v_app        bigint;
  v_rows       integer;
  v_cols       text := 'organisation_id, posted_by_app_user_id, job_title, description, job_category_code, employment_type_code, work_type_code, job_role_id';
BEGIN
  -- ---------------- fixtures (owner) ----------------
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO org.organisation (organisation_name) VALUES ('Acme') RETURNING id INTO v_org_a;
  INSERT INTO org.organisation (organisation_name) VALUES ('Bolt') RETURNING id INTO v_org_b;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'rec@acme.example') RETURNING id INTO v_rec_a;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'rec@bolt.example') RETURNING id INTO v_rec_b;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'consult@example.com') RETURNING id INTO v_consultant;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'ops@talentra.example') RETURNING id INTO v_admin;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'c1@example.com') RETURNING id INTO v_c1;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'c2@example.com') RETURNING id INTO v_c2;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'c3@example.com') RETURNING id INTO v_c3;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'c4@example.com') RETURNING id INTO v_c4;
  INSERT INTO admin.user_role (app_user_id, app_role_code, organisation_id) VALUES (v_rec_a, 'recruiter', v_org_a), (v_rec_b, 'recruiter', v_org_b);
  INSERT INTO admin.user_role (app_user_id, app_role_code) VALUES (v_consultant, 'consultant'), (v_admin, 'admin'),
                                                                  (v_c1, 'candidate'), (v_c2, 'candidate'), (v_c3, 'candidate'), (v_c4, 'candidate');
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_c1, 'Anitha') RETURNING id INTO v_p1;
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_c2, 'Bala') RETURNING id INTO v_p2;
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_c3, 'Chitra') RETURNING id INTO v_p3;
  INSERT INTO profile.candidate_contact (candidate_profile_id, contact_type_code, email) VALUES (v_p2, 'email', 'bala@example.com');
  INSERT INTO admin.block_list (blocker_app_user_id, blocked_organisation_id) VALUES (v_c2, v_org_a);          -- Bala blocks Acme
  INSERT INTO notif.user_preference (app_user_id, ui_language_id, profile_visibility_code)
  SELECT v_c3, id, 'hidden' FROM ref.language WHERE code = 'en';                                              -- Chitra is hidden
  SELECT id INTO v_role FROM ref.job_role WHERE role_name = 'Data Analyst';
  EXECUTE format('INSERT INTO job.job_requirement (%s, job_requirement_status_code, publish_state_code, published_at, is_open_to_consultant, consultant_fee_pct) '
                 || 'VALUES (%s, %s, %L, %L, %L, %L, %L, %s, %L, %L, now(), true, 8) RETURNING id',
                 v_cols, v_org_a, v_rec_a, 'Analyst', 'SQL', 'permanent', 'permanent', 'hybrid', v_role, 'open', 'published') INTO v_ja1;
  EXECUTE format('INSERT INTO job.job_requirement (%s) VALUES (%s, %s, %L, %L, %L, %L, %L, %s) RETURNING id',
                 v_cols, v_org_a, v_rec_a, 'Draft role', 'TBD', 'permanent', 'permanent', 'hybrid', v_role) INTO v_ja2;
  EXECUTE format('INSERT INTO job.job_requirement (%s, job_requirement_status_code, publish_state_code, published_at) '
                 || 'VALUES (%s, %s, %L, %L, %L, %L, %L, %s, %L, %L, now()) RETURNING id',
                 v_cols, v_org_b, v_rec_b, 'Engineer', 'Go', 'permanent', 'permanent', 'remote', v_role, 'open', 'published') INTO v_jb1;
  INSERT INTO job.application (job_requirement_id, candidate_profile_id) VALUES (v_ja1, v_p1) RETURNING id INTO v_app;

  -- F3 (owner context): the interviewer must belong to the job's organisation
  PERFORM qa.expect_error('interviewer from another company',
    format('INSERT INTO job.interview (application_id, candidate_profile_id, round_number, interview_mode_code, scheduled_start, scheduled_end, meeting_url, interviewer_app_user_id) '
           || 'VALUES (%s, %s, 1, %L, now(), now() + interval %L, %L, %s)', v_app, v_p1, 'video', '1 hour', 'https://meet.example.com/a', v_rec_b),
    'trg_interview_interviewer_organisation');
  PERFORM qa.expect_ok('interviewer from the hiring company',
    format('INSERT INTO job.interview (application_id, candidate_profile_id, round_number, interview_mode_code, scheduled_start, scheduled_end, meeting_url, interviewer_app_user_id) '
           || 'VALUES (%s, %s, 1, %L, now(), now() + interval %L, %L, %s)', v_app, v_p1, 'video', '1 hour', 'https://meet.example.com/a', v_rec_a));

  -- the harness must be callable by the application role (rolled back with the test)
  GRANT USAGE ON SCHEMA qa TO talentra_app;
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA qa TO talentra_app;
  EXECUTE 'SET LOCAL ROLE talentra_app';

  -- ---------------- recruiter of Acme ----------------
  PERFORM set_config('app.current_user_id', v_rec_a::text, true);
  PERFORM qa.assert_equals('recruiter sees only own company''s jobs (published and draft)',
    (SELECT string_agg(id::text, ',' ORDER BY id) FROM job.job_requirement WHERE id IN (v_ja1, v_ja2, v_jb1)),
    concat_ws(',', v_ja1, v_ja2));
  UPDATE job.job_requirement SET job_title = 'Hijacked' WHERE id = v_jb1;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM qa.assert_equals('recruiter cannot change another company''s job (0 rows)', v_rows, 0);
  PERFORM qa.expect_error('recruiter cannot post a job for another company',
    format('INSERT INTO job.job_requirement (%s) VALUES (%s, %s, %L, %L, %L, %L, %L, %s)',
           v_cols, v_org_b, v_rec_a, 'Fake', 'Fake', 'permanent', 'permanent', 'onsite', v_role),
    'row-level security');
  PERFORM qa.expect_ok('recruiter posts for own company',
    format('INSERT INTO job.job_requirement (%s) VALUES (%s, %s, %L, %L, %L, %L, %L, %s)',
           v_cols, v_org_a, v_rec_a, 'New role', 'Details', 'permanent', 'permanent', 'onsite', v_role));
  PERFORM qa.assert_equals('blocked and hidden candidates are invisible to the recruiter',
    (SELECT string_agg(id::text, ',') FROM profile.candidate_profile WHERE id IN (v_p1, v_p2, v_p3)), v_p1::text);
  PERFORM qa.assert('blocker''s contact details are invisible too',
    NOT EXISTS (SELECT 1 FROM profile.candidate_contact WHERE candidate_profile_id = v_p2));
  PERFORM qa.assert_equals('recruiter sees applications to own jobs', (SELECT count(*) FROM job.application)::int, 1);
  PERFORM qa.expect_error('recruiter cannot register a candidate',
    format('INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (%s, %L)', v_c4, 'Registered by recruiter'),
    'row-level security');

  -- ---------------- recruiter of Bolt ----------------
  PERFORM set_config('app.current_user_id', v_rec_b::text, true);
  PERFORM qa.assert_equals('other recruiter sees only Bolt jobs',
    (SELECT string_agg(id::text, ',') FROM job.job_requirement WHERE id IN (v_ja1, v_ja2, v_jb1)), v_jb1::text);
  PERFORM qa.assert('a block on Acme does not hide the candidate from Bolt',
    EXISTS (SELECT 1 FROM profile.candidate_profile WHERE id = v_p2));
  PERFORM qa.assert_equals('Bolt sees no applications to Acme jobs', (SELECT count(*) FROM job.application)::int, 0);

  -- ---------------- consultant ----------------
  PERFORM set_config('app.current_user_id', v_consultant::text, true);
  PERFORM qa.assert_equals('consultant sees only published jobs open to consultants',
    (SELECT string_agg(id::text, ',') FROM job.job_requirement WHERE id IN (v_ja1, v_ja2, v_jb1)), v_ja1::text);

  -- ---------------- candidate ----------------
  PERFORM set_config('app.current_user_id', v_c1::text, true);
  PERFORM qa.assert_equals('candidate sees published jobs only',
    (SELECT string_agg(id::text, ',' ORDER BY id) FROM job.job_requirement WHERE id IN (v_ja1, v_ja2, v_jb1)), concat_ws(',', v_ja1, v_jb1));
  PERFORM qa.assert_equals('candidate sees only their own profile',
    (SELECT string_agg(id::text, ',') FROM profile.candidate_profile WHERE id IN (v_p1, v_p2, v_p3)), v_p1::text);
  PERFORM qa.assert_equals('candidate sees only their own applications', (SELECT count(*) FROM job.application)::int, 1);
  PERFORM set_config('app.current_user_id', v_c4::text, true);
  PERFORM qa.expect_ok('a user registers their own candidate profile',
    format('INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (%s, %L)', v_c4, 'Deepa'));

  -- ---------------- guest (no session actor) ----------------
  PERFORM set_config('app.current_user_id', '', true);
  PERFORM qa.assert_equals('guest sees published jobs only',
    (SELECT count(*) FROM job.job_requirement WHERE id IN (v_ja1, v_ja2, v_jb1))::int, 2);
  PERFORM qa.assert_equals('guest sees no candidate profiles', (SELECT count(*) FROM profile.candidate_profile)::int, 0);

  -- ---------------- platform admin ----------------
  PERFORM set_config('app.current_user_id', v_admin::text, true);
  PERFORM qa.assert_equals('admin sees every profile',
    (SELECT count(*) FROM profile.candidate_profile WHERE id IN (v_p1, v_p2, v_p3))::int, 3);

  -- ---------------- privileges that are not row-based ----------------
  PERFORM qa.expect_error('application role cannot edit the audit trail',
    $q$UPDATE audit.audit_event SET audit_action_code = 'login_failed'$q$, 'permission denied');
  PERFORM qa.expect_error('application role cannot write the ledger directly',
    $q$INSERT INTO billing.wallet_ledger_entry (wallet_id, ledger_entry_type_code, amount, currency_code, balance_after, idempotency_key) VALUES (1, 'grant', 1, 'INR', 1, 'x')$q$,
    'permission denied');
  EXECUTE 'RESET ROLE';
END
$test$;
