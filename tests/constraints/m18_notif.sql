-- M18 gate, Notifications, preferences and community (B57): preferences, monthly-partitioned deliveries,
-- provider idempotency, partition maintenance.

DO $test$
DECLARE
  v_user     bigint;
  v_profile  bigint;
  v_search   bigint;
  v_note     bigint;
  v_del      bigint;
  v_queued   timestamptz := timestamptz '2026-10-15 10:00:00+00';
  v_parts    integer;
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'notify.me@example.com') RETURNING id INTO v_user;
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_user, 'Ishaan') RETURNING id INTO v_profile;
  INSERT INTO job.saved_search (candidate_profile_id, search_name, search_criteria)
  VALUES (v_profile, 'Data roles in Chennai', '{"role": "Data Analyst", "city": "Chennai"}') RETURNING id INTO v_search;

  -- preferences
  PERFORM qa.expect_error('UI language the UI is not translated into',
    format('INSERT INTO notif.user_preference (app_user_id, ui_language_id) SELECT %s, id FROM ref.language WHERE code = %L', v_user, 'te'),
    'trg_user_preference_ui_language');
  PERFORM qa.expect_ok('Hindi UI with privacy settings',
    format('INSERT INTO notif.user_preference (app_user_id, ui_language_id, profile_visibility_code) SELECT %s, id, %L FROM ref.language WHERE code = %L',
           v_user, 'applied_only', 'hi'));
  INSERT INTO notif.notification_preference (app_user_id, notification_event_type_code, notification_channel_code, is_enabled)
  VALUES (v_user, 'job_alert', 'sms', false);
  PERFORM qa.expect_error('duplicate preference for the same event and channel',
    format('INSERT INTO notif.notification_preference (app_user_id, notification_event_type_code, notification_channel_code) VALUES (%s, %L, %L)',
           v_user, 'job_alert', 'sms'),
    'uq_notification_preference_user_event_channel');
  INSERT INTO notif.job_alert (candidate_profile_id, saved_search_id, alert_frequency_code) VALUES (v_profile, v_search, 'daily');
  PERFORM qa.expect_error('two email alerts on the same saved search',
    format('INSERT INTO notif.job_alert (candidate_profile_id, saved_search_id) VALUES (%s, %s)', v_profile, v_search),
    'uq_job_alert_saved_search_id_channel');

  -- notifications store a message key, not a body
  PERFORM qa.expect_error('notification whose message key does not exist',
    format('INSERT INTO notif.notification (recipient_app_user_id, notification_event_type_code, message_label_key) VALUES (%s, %L, %L)',
           v_user, 'job_alert', 'msg.does_not_exist'),
    'fk_notification_message_label_key');
  INSERT INTO notif.notification (recipient_app_user_id, notification_event_type_code, message_label_key, message_parameters)
  VALUES (v_user, 'job_alert', 'enum.notification_event_type.job_alert', '{"matches": 4}') RETURNING id INTO v_note;

  -- B57: monthly partitions
  PERFORM qa.assert_equals('notification_delivery is range-partitioned on queued_at',
    pg_get_partkeydef('notif.notification_delivery'::regclass), 'RANGE (queued_at)');
  INSERT INTO notif.notification_delivery (notification_id, notification_channel_code, queued_at)
  VALUES (v_note, 'email', v_queued) RETURNING id INTO v_del;
  PERFORM qa.assert_equals('a delivery lands in its month''s partition',
    (SELECT tableoid::regclass::text FROM notif.notification_delivery WHERE id = v_del), 'notif.notification_delivery_p202610');
  INSERT INTO notif.notification_delivery (notification_id, notification_channel_code, queued_at)
  VALUES (v_note, 'push', timestamptz '2031-01-01 00:00:00+00');
  PERFORM qa.assert('a delivery outside the prepared months lands in the default partition',
    EXISTS (SELECT 1 FROM notif.notification_delivery_default WHERE notification_channel_code = 'push'));
  PERFORM qa.assert('partition pruning: a one-month query touches one partition',
    position('notification_delivery_p202610' IN
      (SELECT string_agg(l, ' ') FROM (SELECT * FROM qa.explain_lines(format(
        'SELECT * FROM notif.notification_delivery WHERE queued_at >= %L AND queued_at < %L', '2026-10-01', '2026-11-01'))) e(l))) > 0
    AND position('notification_delivery_p202611' IN
      (SELECT string_agg(l, ' ') FROM (SELECT * FROM qa.explain_lines(format(
        'SELECT * FROM notif.notification_delivery WHERE queued_at >= %L AND queued_at < %L', '2026-10-01', '2026-11-01'))) e(l))) = 0);

  -- delivery rules and provider idempotency
  PERFORM qa.expect_error('failed delivery without a reason',
    format('UPDATE notif.notification_delivery SET delivery_status_code = %L WHERE id = %s', 'failed', v_del),
    'ck_notification_delivery_failure');
  PERFORM qa.expect_error('sent status without a send time',
    format('UPDATE notif.notification_delivery SET delivery_status_code = %L WHERE id = %s', 'sent', v_del),
    'ck_notification_delivery_sent');
  UPDATE notif.notification_delivery SET delivery_status_code = 'sent', sent_at = v_queued + interval '5 seconds' WHERE id = v_del;
  INSERT INTO notif.delivery_provider_receipt (notification_channel_code, provider_message_reference, notification_delivery_id, delivery_queued_at)
  VALUES ('email', 'ses-0001', v_del, v_queued);
  PERFORM qa.expect_error('duplicate provider message id (replayed callback)',
    format('INSERT INTO notif.delivery_provider_receipt (notification_channel_code, provider_message_reference, notification_delivery_id, delivery_queued_at) '
           || 'SELECT %L, %L, id, queued_at FROM notif.notification_delivery WHERE notification_channel_code = %L',
           'email', 'ses-0001', 'push'),
    'uq_delivery_provider_receipt_provider_message');

  -- partition maintenance: create ahead, detach old months for retention
  PERFORM qa.assert_equals('ensure_delivery_partitions creates missing months only', notif.ensure_delivery_partitions(DATE '2027-11-01', 3), 1);
  SELECT count(*) INTO v_parts FROM pg_inherits WHERE inhparent = 'notif.notification_delivery'::regclass;
  EXECUTE 'ALTER TABLE notif.notification_delivery DETACH PARTITION notif.notification_delivery_p202601';
  PERFORM qa.assert_equals('detaching an old month removes it from the table',
    (SELECT count(*) FROM pg_inherits WHERE inhparent = 'notif.notification_delivery'::regclass)::int, v_parts - 1);

  -- community and support
  PERFORM qa.expect_error('blank community post',
    format('INSERT INTO notif.community_post (author_app_user_id, post_body) VALUES (%s, %L)', v_user, '   '),
    'ck_community_post_post_body_not_blank');
  PERFORM qa.expect_error('ticket resolved without a resolution time',
    format('INSERT INTO notif.support_ticket (requester_app_user_id, ticket_category_code, ticket_status_code, ticket_subject) VALUES (%s, %L, %L, %L)',
           v_user, 'account', 'resolved', 'Cannot log in'),
    'ck_support_ticket_resolved');
END
$test$;
