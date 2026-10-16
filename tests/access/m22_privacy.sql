-- M22 gate, privacy (B75-B79): RLS on every Personal table of the profile, anonymisation on request, and the retention
-- job. RLS checks run as talentra_app; anonymisation and retention are checked through their audited functions.

DO $test$
DECLARE
  v_org     bigint;
  v_rec     bigint;
  v_c1      bigint;
  v_c2      bigint;
  v_c3      bigint;
  v_c4      bigint;
  v_p1      bigint;
  v_p2      bigint;
  v_p3      bigint;
  v_p4      bigint;
  v_job     bigint;
  v_app     bigint;
  v_role    bigint;
  v_skill   bigint;
  v_city    bigint;
  v_rv      bigint;
  v_res     jsonb;
  v_note    bigint;
  v_rows    integer;
BEGIN
  -- ---------------- fixtures (owner) ----------------
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO org.organisation (organisation_name) VALUES ('Acme') RETURNING id INTO v_org;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'rec@acme.example') RETURNING id INTO v_rec;
  INSERT INTO admin.app_user (user_status_code, login_email, last_login_at) VALUES ('active', 'c1@example.com', now()) RETURNING id INTO v_c1;
  INSERT INTO admin.app_user (user_status_code, login_email, last_login_at) VALUES ('active', 'c2@example.com', now()) RETURNING id INTO v_c2;
  INSERT INTO admin.app_user (user_status_code, login_email, last_login_at) VALUES ('active', 'c3@example.com', now()) RETURNING id INTO v_c3;
  INSERT INTO admin.app_user (user_status_code, login_email, last_login_at, created_at)
       VALUES ('active', 'c4@example.com', now() - interval '37 months', now() - interval '40 months') RETURNING id INTO v_c4;
  INSERT INTO admin.user_role (app_user_id, app_role_code, organisation_id) VALUES (v_rec, 'recruiter', v_org);
  INSERT INTO admin.user_role (app_user_id, app_role_code) VALUES (v_c1, 'candidate'), (v_c2, 'candidate'), (v_c3, 'candidate'), (v_c4, 'candidate');
  INSERT INTO profile.candidate_profile (app_user_id, full_name, given_name, headline) VALUES (v_c1, 'Anitha Raman', 'Anitha', 'Analyst') RETURNING id INTO v_p1;
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_c2, 'Bala') RETURNING id INTO v_p2;
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_c3, 'Chitra') RETURNING id INTO v_p3;
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_c4, 'Dinesh') RETURNING id INTO v_p4;
  SELECT min(id) INTO v_skill FROM ref.skill;
  SELECT min(id) INTO v_city FROM ref.city;
  INSERT INTO profile.candidate_contact (candidate_profile_id, contact_type_code, email) VALUES (v_p1, 'email', 'anitha@example.com'), (v_p2, 'email', 'bala@example.com');
  INSERT INTO profile.candidate_address (candidate_profile_id, address_type_code, address_line1, city_id) VALUES (v_p1, 'current', '1 Lake Road', v_city), (v_p2, 'current', '2 Hill Road', v_city);
  INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id) VALUES (v_p1, v_skill), (v_p2, v_skill);
  INSERT INTO profile.candidate_web_link (candidate_profile_id, web_link_type_code, link_url) VALUES (v_p1, 'github', 'https://github.example/anitha');
  INSERT INTO profile.candidate_identity_document (candidate_profile_id, identifier_type_code, verification_token, identifier_hash, identifier_last4, verification_status_code, verified_at)
       VALUES (v_p1, 'aadhaar', 'tok_anitha', digest('aadhaar:1', 'sha256'), '1234', 'verified', now());
  INSERT INTO profile.resume_version (candidate_profile_id, version_number, body, is_default) VALUES (v_p1, 1, 'Anitha Raman, SQL analyst', true) RETURNING id INTO v_rv;
  INSERT INTO admin.block_list (blocker_app_user_id, blocked_organisation_id) VALUES (v_c2, v_org);   -- Bala blocks Acme
  SELECT id INTO v_role FROM ref.job_role WHERE role_name = 'Data Analyst';
  INSERT INTO job.job_requirement (organisation_id, posted_by_app_user_id, job_title, description, job_category_code, employment_type_code,
                                   work_type_code, job_role_id, job_requirement_status_code, publish_state_code, published_at)
       VALUES (v_org, v_rec, 'Analyst', 'SQL', 'permanent', 'permanent', 'hybrid', v_role, 'open', 'published', now()) RETURNING id INTO v_job;
  INSERT INTO job.application (job_requirement_id, candidate_profile_id, resume_version_id, cover_note) VALUES (v_job, v_p1, v_rv, 'I am Anitha, call me on 98400 12345') RETURNING id INTO v_app;

  GRANT USAGE ON SCHEMA qa TO talentra_app;
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA qa TO talentra_app;
  EXECUTE 'SET LOCAL ROLE talentra_app';

  -- ---------------- RLS on the profile's Personal tables ----------------
  PERFORM set_config('app.current_user_id', v_rec::text, true);
  PERFORM qa.assert('recruiter sees a visible candidate''s address, skills, links and resume',
    EXISTS (SELECT 1 FROM profile.candidate_address WHERE candidate_profile_id = v_p1)
    AND EXISTS (SELECT 1 FROM profile.candidate_skill WHERE candidate_profile_id = v_p1)
    AND EXISTS (SELECT 1 FROM profile.candidate_web_link WHERE candidate_profile_id = v_p1)
    AND EXISTS (SELECT 1 FROM profile.resume_version WHERE candidate_profile_id = v_p1));
  PERFORM qa.assert('recruiter sees nothing of a candidate who blocked the company (address, skills)',
    NOT EXISTS (SELECT 1 FROM profile.candidate_address WHERE candidate_profile_id = v_p2)
    AND NOT EXISTS (SELECT 1 FROM profile.candidate_skill WHERE candidate_profile_id = v_p2));
  PERFORM qa.assert_equals('identity documents are never visible to the hiring side',
    (SELECT count(*) FROM profile.candidate_identity_document)::int, 0);
  PERFORM qa.expect_error('recruiter cannot add a skill to a candidate',
    format('INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id) VALUES (%s, %s)', v_p3, v_skill), 'row-level security');
  UPDATE profile.candidate_address SET address_line1 = 'Changed' WHERE candidate_profile_id = v_p1;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM qa.assert_equals('recruiter cannot change a candidate''s address (0 rows)', v_rows, 0);
  PERFORM qa.expect_error('name search needs at least 3 characters', 'SELECT * FROM app.search_candidates_by_name(''ab'')', 'at least 3 characters');
  PERFORM qa.assert_equals('name search finds visible candidates and excludes one who blocked the company',
    (SELECT string_agg(candidate_profile_id::text, ',' ORDER BY candidate_profile_id)
       FROM (SELECT candidate_profile_id FROM app.search_candidates_by_name('Anitha') UNION ALL
             SELECT candidate_profile_id FROM app.search_candidates_by_name('Bala') UNION ALL
             SELECT candidate_profile_id FROM app.search_candidates_by_name('Chitra')) s), concat_ws(',', v_p1, v_p3));
  PERFORM qa.assert_equals('name search treats % and _ as literal characters',
    (SELECT count(*) FROM app.search_candidates_by_name('%%%'))::int, 0);
  PERFORM qa.expect_error('recruiter cannot anonymise a candidate', format('SELECT admin.anonymise_user(%s, %L)', v_c1, 'test'), 'may not anonymise');

  PERFORM set_config('app.current_user_id', v_c2::text, true);
  PERFORM qa.assert_equals('a candidate sees only their own address', (SELECT count(*) FROM profile.candidate_address)::int, 1);
  PERFORM qa.expect_ok('a candidate adds their own skill',
    format('INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id) VALUES (%s, %s)', v_p2, (SELECT max(id) FROM ref.skill)));

  PERFORM qa.assert_equals('a candidate''s name search returns nothing (candidates never search candidates)',
    (SELECT count(*) FROM app.search_candidates_by_name('Anitha'))::int, 0);

  PERFORM set_config('app.current_user_id', v_c1::text, true);
  PERFORM qa.assert_equals('a candidate sees their own identity document', (SELECT count(*) FROM profile.candidate_identity_document)::int, 1);

  -- ---------------- anonymisation on request (the candidate themself) ----------------
  v_res := admin.anonymise_user(v_c1, 'deletion request');
  PERFORM qa.assert('anonymise_user reports what it removed', (v_res -> 'rows' ->> 'candidate_contact')::int = 1, v_res::text);
  EXECUTE 'RESET ROLE';
  PERFORM set_config('app.current_user_id', '1', true);
  PERFORM qa.assert('profile keeps its row but loses every Personal value',
    (SELECT full_name = 'Anonymised user' AND given_name IS NULL AND headline IS NULL AND deleted_at IS NOT NULL
       FROM profile.candidate_profile WHERE id = v_p1));
  PERFORM qa.assert('contacts, address, links and identity documents are deleted',
    NOT EXISTS (SELECT 1 FROM profile.candidate_contact WHERE candidate_profile_id = v_p1)
    AND NOT EXISTS (SELECT 1 FROM profile.candidate_address WHERE candidate_profile_id = v_p1)
    AND NOT EXISTS (SELECT 1 FROM profile.candidate_web_link WHERE candidate_profile_id = v_p1)
    AND NOT EXISTS (SELECT 1 FROM profile.candidate_identity_document WHERE candidate_profile_id = v_p1));
  PERFORM qa.assert_equals('the resume referenced by an application stays but is blanked',
    (SELECT body FROM profile.resume_version WHERE id = v_rv)::text, '[anonymised]');
  PERFORM qa.assert('the application and its status history survive (pipeline history is kept)',
    EXISTS (SELECT 1 FROM job.application WHERE id = v_app)
    AND EXISTS (SELECT 1 FROM job.application_status_history WHERE application_id = v_app));
  PERFORM qa.assert('the application''s cover note (candidate free text) is cleared',
    (SELECT cover_note IS NULL FROM job.application WHERE id = v_app));
  PERFORM qa.assert('the login identity has no identifier left and is deactivated',
    (SELECT login_email IS NULL AND login_phone IS NULL AND display_name IS NULL AND user_status_code = 'deactivated'
            AND anonymised_at IS NOT NULL FROM admin.app_user WHERE id = v_c1));
  PERFORM qa.assert('anonymisation is audited with the reason',
    EXISTS (SELECT 1 FROM audit.audit_event WHERE audit_action_code = 'user_anonymised' AND subject_id = v_c1
             AND event_detail ->> 'reason' = 'deletion request'));
  PERFORM qa.assert('anonymise_user is idempotent', admin.anonymise_user(v_c1, 'again') ? 'already_anonymised_at');
  PERFORM qa.expect_ok('the freed email can register again',
    $q$INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'c1@example.com')$q$);
  PERFORM qa.expect_error('the system actor cannot be anonymised', 'SELECT admin.anonymise_user(1, ''x'')', 'system actor');

  -- ---------------- retention job ----------------
  PERFORM set_config('app.current_user_id', v_rec::text, true);
  PERFORM qa.expect_error('only the system actor runs the retention job', 'SELECT admin.run_retention()', 'run_retention');
  PERFORM set_config('app.current_user_id', '1', true);
  UPDATE profile.candidate_profile SET deleted_at = now() - interval '31 days' WHERE id = v_p2;   -- deletion requested 31 days ago
  UPDATE profile.candidate_profile SET deleted_at = now() - interval '10 days' WHERE id = v_p3;   -- requested 10 days ago
  INSERT INTO audit.error_log (error_severity_code, error_code, error_message, occurred_at)
       VALUES ('error', 'E1', 'old error', now() - interval '100 days'), ('error', 'E2', 'recent error', now() - interval '5 days');
  INSERT INTO lic.login_attempt (app_user_id, login_outcome_code, attempted_at)
       VALUES (v_rec, 'bad_credentials', now() - interval '2 years'), (v_rec, 'bad_credentials', now() - interval '1 day');
  INSERT INTO notif.notification (recipient_app_user_id, notification_event_type_code, message_label_key, created_at)
       VALUES (v_rec, 'job_alert', 'enum.notification_event_type.job_alert', now() - interval '200 days') RETURNING id INTO v_note;
  INSERT INTO notif.notification_delivery (notification_id, notification_channel_code, delivery_status_code, queued_at)
       VALUES (v_note, 'email', 'queued', now() - interval '200 days');
  PERFORM qa.expect_error('append-only rows cannot be deleted outside the retention job',
    'DELETE FROM audit.error_log WHERE error_code = ''E1''', 'forbid_update_delete');

  v_res := admin.run_retention();
  PERFORM qa.assert('a deletion request older than 30 days is anonymised; a newer one is not',
    (SELECT anonymised_at IS NOT NULL FROM admin.app_user WHERE id = v_c2) AND (SELECT anonymised_at IS NULL FROM admin.app_user WHERE id = v_c3), v_res::text);
  PERFORM qa.assert('a candidate inactive for 36 months is anonymised; an active one is not',
    (SELECT anonymised_at IS NOT NULL FROM admin.app_user WHERE id = v_c4)
    AND (SELECT full_name FROM profile.candidate_profile WHERE id = v_p4) = 'Anonymised user');
  PERFORM qa.assert('error log: 90-day window applied (old row gone, recent row kept)',
    NOT EXISTS (SELECT 1 FROM audit.error_log WHERE error_code = 'E1') AND EXISTS (SELECT 1 FROM audit.error_log WHERE error_code = 'E2'));
  PERFORM qa.assert('login attempts: 1-year window applied',
    (SELECT count(*) FROM lic.login_attempt WHERE app_user_id = v_rec) = 1);
  PERFORM qa.assert('notifications older than 180 days are gone with their deliveries',
    NOT EXISTS (SELECT 1 FROM notif.notification WHERE id = v_note)
    AND NOT EXISTS (SELECT 1 FROM notif.notification_delivery WHERE notification_id = v_note));
  PERFORM qa.assert('delivery months past the window are dropped as partitions',
    (v_res ->> 'delivery_partitions_dropped')::int > 0
    AND to_regclass('notif.notification_delivery_p' || to_char(now() - interval '1 month', 'YYYYMM')) IS NOT NULL, v_res::text);
  PERFORM qa.assert('the retention run is audited with its counts',
    EXISTS (SELECT 1 FROM audit.audit_event WHERE audit_action_code = 'retention_purged' AND event_detail ? 'error_log'));
  PERFORM qa.expect_error('after the run, append-only deletes are blocked again',
    'DELETE FROM audit.error_log WHERE error_code = ''E2''', 'forbid_update_delete');

  -- the purge flag gives the application role nothing: it holds no DELETE grant on append-only tables
  EXECUTE 'SET LOCAL ROLE talentra_app';
  PERFORM set_config('app.retention_purge', 'on', true);
  PERFORM qa.expect_error('the application role cannot use the purge flag', 'DELETE FROM audit.error_log', 'permission denied');
  PERFORM qa.expect_error('the application role cannot run the retention job', 'SELECT admin.run_retention()', 'permission denied');
END
$test$;
