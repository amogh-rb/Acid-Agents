-- M14 gate, Licences, seats, devices and sessions (B45, RG9).

DO $test$
DECLARE
  v_account  bigint;
  v_licence  bigint;
  v_user     bigint;
  v_user2    bigint;
  v_user3    bigint;
  v_s1       bigint;
  v_s2       bigint;
  v_r        record;
  v_device   bigint;
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO org.account (account_name, account_status_code) VALUES ('Acme Staffing', 'active') RETURNING id INTO v_account;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'r1@acme.example') RETURNING id INTO v_user;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'r2@acme.example') RETURNING id INTO v_user2;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'r3@acme.example') RETURNING id INTO v_user3;

  -- RG9: both limits are explicit positive columns
  PERFORM qa.expect_error('max_devices_per_user = 0',
    format('INSERT INTO lic.licence (account_id, licence_name, max_users, max_devices_per_user) VALUES (%s, %L, 2, 0)', v_account, 'Bad'),
    'ck_licence_max_devices_per_user_positive');
  PERFORM qa.expect_error('max_users = 0',
    format('INSERT INTO lic.licence (account_id, licence_name, max_users, max_devices_per_user) VALUES (%s, %L, 0, 2)', v_account, 'Bad'),
    'ck_licence_max_users_positive');
  INSERT INTO lic.licence (account_id, licence_name, max_users, max_devices_per_user)
  VALUES (v_account, 'Acme Pro', 2, 2) RETURNING id INTO v_licence;

  -- seats: max_users enforced under a lock on the licence row
  INSERT INTO lic.licence_seat (licence_id, app_user_id) VALUES (v_licence, v_user), (v_licence, v_user2);
  PERFORM qa.expect_error('third seat on a 2-user licence',
    format('INSERT INTO lic.licence_seat (licence_id, app_user_id) VALUES (%s, %s)', v_licence, v_user3), 'trg_licence_seat_limit');
  PERFORM qa.expect_error('second active seat for the same user (on another licence)',
    format('WITH l AS (INSERT INTO lic.licence (account_id, licence_name, max_users, max_devices_per_user) VALUES (%s, %L, 5, 1) RETURNING id) '
           || 'INSERT INTO lic.licence_seat (licence_id, app_user_id) SELECT id, %s FROM l', v_account, 'Acme Spare', v_user),
    'uq_licence_seat_active_user');
  PERFORM qa.assert_equals('user without a seat is refused',
    (SELECT outcome FROM app.start_session(v_user3, digest('u3-d1', 'sha256'), digest('u3-t1', 'sha256'))), 'no_seat');

  -- device limit = 2
  PERFORM set_config('app.current_user_id', v_user::text, true);
  SELECT * INTO v_r FROM app.start_session(v_user, digest('laptop', 'sha256'), digest('tok-1', 'sha256'));
  v_s1 := v_r.login_session_id;
  PERFORM qa.assert_equals('first device: session started', v_r.outcome, 'started');
  SELECT * INTO v_r FROM app.start_session(v_user, digest('phone', 'sha256'), digest('tok-2', 'sha256'));
  v_s2 := v_r.login_session_id;
  PERFORM qa.assert_equals('second device: session started', v_r.outcome, 'started');
  SELECT * INTO v_r FROM app.start_session(v_user, digest('tablet', 'sha256'), digest('tok-3', 'sha256'));
  PERFORM qa.assert_equals('third device: rejected at the limit', v_r.outcome, 'device_limit');
  PERFORM qa.assert('rejection is audited as device_limit_exceeded',
    EXISTS (SELECT 1 FROM audit.audit_event WHERE audit_action_code = 'device_limit_exceeded'
              AND (event_detail ->> 'app_user_id')::bigint = v_user AND (event_detail ->> 'limit')::int = 2));
  PERFORM qa.assert('rejection is in the login history',
    EXISTS (SELECT 1 FROM lic.login_attempt WHERE app_user_id = v_user AND login_outcome_code = 'device_limit'));

  -- release by logout
  PERFORM qa.assert('logout releases the session', app.end_session(v_s1));
  PERFORM qa.assert_equals('after logout a new device can log in',
    (SELECT outcome FROM app.start_session(v_user, digest('tablet', 'sha256'), digest('tok-4', 'sha256'))), 'started');

  -- release by revocation (audited) and by expiry; neither counts any more
  PERFORM qa.assert('revoking a session', app.revoke_session(v_s2, 'lost phone'));
  PERFORM qa.assert('revocation is audited and recorded',
    EXISTS (SELECT 1 FROM audit.audit_event WHERE audit_action_code = 'session_revoked' AND subject_id = v_s2)
    AND EXISTS (SELECT 1 FROM lic.session_revocation WHERE login_session_id = v_s2));
  PERFORM qa.assert_equals('a revoked session does not count against the limit',
    (SELECT outcome FROM app.start_session(v_user, digest('desktop', 'sha256'), digest('tok-5', 'sha256'))), 'started');
  UPDATE lic.login_session SET started_at = now() - interval '2 days', last_activity_at = now() - interval '2 days',
                               expires_at = now() - interval '1 day'
   WHERE app_user_id = v_user AND ended_at IS NULL AND session_token_hash = digest('tok-4', 'sha256');
  PERFORM qa.assert_equals('an expired (not yet swept) session does not count',
    (SELECT outcome FROM app.start_session(v_user, digest('kiosk', 'sha256'), digest('tok-6', 'sha256'))), 'started');
  PERFORM qa.assert('the sweep releases expired sessions', app.expire_idle_sessions() >= 1);
  PERFORM qa.assert('swept session is marked expired',
    EXISTS (SELECT 1 FROM lic.login_session WHERE session_token_hash = digest('tok-4', 'sha256') AND session_end_reason_code = 'expired'));

  -- device revocation ends its sessions and blocks it
  SELECT registered_device_id INTO v_device FROM lic.login_session WHERE session_token_hash = digest('tok-5', 'sha256');
  PERFORM qa.assert_equals('revoking a device ends its open session', app.revoke_device(v_device, 'compromised'), 1);
  PERFORM qa.assert_equals('a revoked device cannot start a session',
    (SELECT outcome FROM app.start_session(v_user, digest('desktop', 'sha256'), digest('tok-7', 'sha256'))), 'device_revoked');

  -- integrity
  PERFORM qa.expect_error('session on another user''s device (composite FK)',
    format('INSERT INTO lic.login_session (app_user_id, registered_device_id, licence_seat_id, session_token_hash, expires_at) '
           || 'SELECT %s, %s, s.id, digest(%L, %L), now() + interval %L FROM lic.licence_seat s WHERE s.app_user_id = %s',
           v_user2, v_device, 'x', 'sha256', '1 hour', v_user2),
    'fk_login_session_device');
  PERFORM qa.expect_error('ended session without a reason',
    format('UPDATE lic.login_session SET ended_at = now() WHERE session_token_hash = digest(%L, %L)', 'tok-6', 'sha256'),
    'ck_login_session_end_pair');
  PERFORM qa.assert('application role cannot write sessions directly (session API only)',
    NOT has_table_privilege('talentra_app', 'lic.login_session', 'INSERT')
    AND NOT has_table_privilege('talentra_app', 'lic.login_session', 'UPDATE')
    AND has_function_privilege('talentra_app', 'app.start_session(bigint, bytea, bytea, text, text)', 'EXECUTE'));
END
$test$;
