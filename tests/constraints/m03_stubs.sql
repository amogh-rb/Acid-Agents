-- M3 gate: the stubs apply, give later FKs a target, and the system actor is wired into every audit FK.

DO $test$
DECLARE
  v_user_id bigint;
  v_org_id  bigint;
BEGIN
  PERFORM qa.assert('system actor id 1 exists, active and flagged',
    EXISTS (SELECT 1 FROM admin.app_user WHERE id = 1 AND is_system_actor AND user_status_code = 'active'));
  PERFORM qa.assert('audit FKs to app_user were added to earlier tables (ref.language)',
    EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_language_created_by'));
  PERFORM qa.assert('soft-delete default views exist for both stubs',
    to_regclass('admin.v_app_user') IS NOT NULL AND to_regclass('org.v_organisation') IS NOT NULL);

  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'm03.user@example.com') RETURNING id INTO v_user_id;
  PERFORM qa.assert('identity continues after the system actor (no id collision)', v_user_id >= 2, 'got id ' || v_user_id);

  PERFORM set_config('app.current_user_id', v_user_id::text, true);
  INSERT INTO org.organisation (organisation_name) VALUES ('Northbridge Workforce Systems') RETURNING id INTO v_org_id;
  PERFORM qa.assert_equals('organisation created_by is the acting user',
    (SELECT created_by FROM org.organisation WHERE id = v_org_id), v_user_id);
  PERFORM qa.assert_equals('organisation defaults to pending_verification',
    (SELECT organisation_status_code::text FROM org.organisation WHERE id = v_org_id), 'pending_verification');

  PERFORM qa.expect_error('unknown user status is rejected',
    $q$INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('banned', 'banned@example.com')$q$, 'fk_app_user_user_status_code');
  PERFORM qa.expect_error('unknown organisation status is rejected',
    $q$INSERT INTO org.organisation (organisation_name, organisation_status_code) VALUES ('X', 'gone')$q$,
    'fk_organisation_organisation_status_code');
  PERFORM qa.expect_error('blank organisation name is rejected',
    $q$INSERT INTO org.organisation (organisation_name) VALUES ('  ')$q$, 'ck_organisation_organisation_name_not_blank');
  PERFORM qa.expect_error('system actor cannot be suspended',
    $q$UPDATE admin.app_user SET user_status_code = 'suspended' WHERE id = 1$q$, 'ck_app_user_system_actor_active');
  PERFORM qa.expect_error('system actor cannot be deleted while it owns rows',
    $q$DELETE FROM admin.app_user WHERE id = 1$q$, 'violates RESTRICT setting of foreign key constraint');

  PERFORM set_config('app.current_user_id', '999999', true);
  PERFORM qa.expect_error('an actor that does not exist is rejected',
    $q$INSERT INTO org.organisation (organisation_name) VALUES ('Ghost Ltd')$q$, 'fk_organisation_created_by');
END
$test$;
