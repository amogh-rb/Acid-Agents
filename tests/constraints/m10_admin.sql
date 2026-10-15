-- M10 gate, Administration (B33): credentials, roles, blocking, consent and the append-only audit trail.

DO $test$
DECLARE
  v_admin     bigint;
  v_cand      bigint;
  v_recruiter bigint;
  v_org       bigint;
  v_role_id   bigint;
  v_audit     bigint;
  v_hash      text := '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHQ$RdescudvJCsgt3ub+b+dWRWJTmaaJObG';
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'admin@talentra.example') RETURNING id INTO v_admin;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'meena@example.com') RETURNING id INTO v_cand;
  INSERT INTO admin.app_user (user_status_code, login_phone, login_phone_country_id)
  SELECT 'active', '+919840012345', id FROM ref.country WHERE iso_alpha2 = 'IN' RETURNING id INTO v_recruiter;
  INSERT INTO org.organisation (organisation_name) VALUES ('Acme Staffing') RETURNING id INTO v_org;

  -- login identity
  PERFORM qa.expect_error('active user without any login identifier',
    $q$INSERT INTO admin.app_user (user_status_code) VALUES ('active')$q$, 'ck_app_user_login_identifier');
  PERFORM qa.expect_error('duplicate login email',
    $q$INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'meena@example.com')$q$, 'uq_app_user_login_email');
  PERFORM qa.expect_error('login phone without its country',
    $q$INSERT INTO admin.app_user (user_status_code, login_phone) VALUES ('active', '+14155550100')$q$, 'ck_app_user_login_phone_country');

  -- credentials: hash only, one per user
  INSERT INTO admin.user_credential (app_user_id, password_hash) VALUES (v_cand, v_hash);
  PERFORM qa.expect_error('second credential for the same user',
    format('INSERT INTO admin.user_credential (app_user_id, password_hash) VALUES (%s, %L)', v_cand, v_hash),
    'uq_user_credential_app_user_id');
  PERFORM qa.expect_error('plain-text password is not a PHC hash',
    format('INSERT INTO admin.user_credential (app_user_id, password_hash, hash_algorithm_code) VALUES (%s, %L, %L)',
           v_admin, 'hunter2', 'bcrypt_legacy'),
    'ck_user_credential_password_hash_format');
  PERFORM qa.expect_error('bcrypt hash labelled as argon2id',
    format('INSERT INTO admin.user_credential (app_user_id, password_hash) VALUES (%s, %L)', v_admin,
           '$2b$12$abcdefghijklmnopqrstuuJ0eY2hW7m7Zb6v0bQ2y5tq8yX0bQ2y5'),
    'ck_user_credential_hash_matches_algorithm');
  PERFORM qa.assert('credential change was audited',
    EXISTS (SELECT 1 FROM audit.audit_event WHERE audit_action_code = 'credential_changed'
              AND (event_detail ->> 'app_user_id')::bigint = v_cand));

  -- roles: effective-dated, no overlap, scope rules
  INSERT INTO admin.user_role (app_user_id, app_role_code, valid_period)
  VALUES (v_cand, 'candidate', tstzrange('2026-01-01', NULL)) RETURNING id INTO v_role_id;
  PERFORM qa.expect_error('overlapping grant of the same role',
    format('INSERT INTO admin.user_role (app_user_id, app_role_code, valid_period) VALUES (%s, %L, tstzrange(%L, NULL))',
           v_cand, 'candidate', '2026-05-01'),
    'ex_user_role_no_overlap');
  UPDATE admin.user_role SET valid_period = tstzrange('2026-01-01', '2026-06-01') WHERE id = v_role_id;
  PERFORM qa.expect_ok('back-to-back grant after the first period closes',
    format('INSERT INTO admin.user_role (app_user_id, app_role_code, valid_period) VALUES (%s, %L, tstzrange(%L, NULL))',
           v_cand, 'candidate', '2026-06-01'));
  PERFORM qa.expect_error('organisation-scoped role without an organisation',
    format('INSERT INTO admin.user_role (app_user_id, app_role_code) VALUES (%s, %L)', v_recruiter, 'recruiter'),
    'trg_user_role_scope');
  PERFORM qa.expect_error('platform role scoped to an organisation',
    format('INSERT INTO admin.user_role (app_user_id, app_role_code, organisation_id) VALUES (%s, %L, %s)', v_cand, 'admin', v_org),
    'trg_user_role_scope');
  PERFORM qa.expect_ok('recruiter role for an organisation',
    format('INSERT INTO admin.user_role (app_user_id, app_role_code, organisation_id) VALUES (%s, %L, %s)', v_recruiter, 'recruiter', v_org));
  PERFORM qa.assert('role grants and revocations were audited',
    (SELECT count(*) FROM audit.audit_event WHERE audit_action_code IN ('role_granted', 'role_revoked')) >= 4);
  PERFORM qa.assert('recruiter role carries the candidate_search permission',
    EXISTS (SELECT 1 FROM admin.app_role_permission WHERE app_role_code = 'recruiter' AND permission_code = 'candidate_search'));

  -- blocking
  PERFORM set_config('app.current_user_id', v_cand::text, true);
  PERFORM qa.expect_error('block row naming both a user and an organisation',
    format('INSERT INTO admin.block_list (blocker_app_user_id, blocked_app_user_id, blocked_organisation_id) VALUES (%s, %s, %s)',
           v_cand, v_recruiter, v_org),
    'ck_block_list_single_target');
  PERFORM qa.expect_error('block row naming no target',
    format('INSERT INTO admin.block_list (blocker_app_user_id) VALUES (%s)', v_cand), 'ck_block_list_single_target');
  PERFORM qa.expect_error('blocking yourself',
    format('INSERT INTO admin.block_list (blocker_app_user_id, blocked_app_user_id) VALUES (%s, %s)', v_cand, v_cand),
    'ck_block_list_not_self');
  INSERT INTO admin.block_list (blocker_app_user_id, blocked_organisation_id) VALUES (v_cand, v_org);
  PERFORM qa.expect_error('duplicate active block of the same company',
    format('INSERT INTO admin.block_list (blocker_app_user_id, blocked_organisation_id) VALUES (%s, %s)', v_cand, v_org),
    'uq_block_list_active_organisation_pair');
  UPDATE admin.block_list SET deleted_at = now() WHERE blocker_app_user_id = v_cand;
  PERFORM qa.expect_ok('block again after unblocking (history kept)',
    format('INSERT INTO admin.block_list (blocker_app_user_id, blocked_organisation_id) VALUES (%s, %s)', v_cand, v_org));
  PERFORM qa.assert_equals('block, unblock and re-block are all audited',
    (SELECT count(*) FROM audit.audit_event WHERE audit_action_code IN ('block_added', 'block_removed') AND actor_app_user_id = v_cand)::int, 3);

  -- consent: append-only, withdrawal is a new row
  INSERT INTO admin.consent_record (app_user_id, consent_purpose_code, is_granted, policy_version) VALUES (v_cand, 'marketing_email', true, '2026.1');
  INSERT INTO admin.consent_record (app_user_id, consent_purpose_code, is_granted, policy_version) VALUES (v_cand, 'marketing_email', false, '2026.1');
  PERFORM qa.expect_error('consent rows cannot be edited',
    format('UPDATE admin.consent_record SET is_granted = true WHERE app_user_id = %s', v_cand), 'forbid_update_delete');
  PERFORM qa.assert('latest consent row is the withdrawal',
    (SELECT NOT is_granted FROM admin.consent_record WHERE app_user_id = v_cand AND consent_purpose_code = 'marketing_email'
      ORDER BY recorded_at DESC, id DESC LIMIT 1));

  -- audit trail: written through log_event with the session actor; append-only
  v_audit := audit.log_event('profile_viewed', 'profile.candidate_profile', 42, '{"source": "search"}');
  PERFORM qa.assert_equals('log_event records the session actor, not a parameter',
    (SELECT actor_app_user_id FROM audit.audit_event WHERE id = v_audit), v_cand);
  PERFORM qa.expect_error('UPDATE of an audit row',
    format('UPDATE audit.audit_event SET audit_action_code = %L WHERE id = %s', 'login_failed', v_audit), 'forbid_update_delete');
  PERFORM qa.expect_error('DELETE of an audit row',
    format('DELETE FROM audit.audit_event WHERE id = %s', v_audit), 'forbid_update_delete');
  PERFORM qa.expect_error('free-text audit action',
    $q$SELECT audit.log_event('hacked', 'admin.app_user', 1)$q$, 'fk_audit_event_audit_action_code');
  PERFORM qa.assert('application role cannot update or delete the audit trail',
    NOT has_table_privilege('talentra_app', 'audit.audit_event', 'UPDATE')
    AND NOT has_table_privilege('talentra_app', 'audit.audit_event', 'DELETE'));
END
$test$;
