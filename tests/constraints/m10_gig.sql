-- M10 gate, Gig marketplace (B35): windows, pricing, one-way bids, non-overlapping assignments, handoff idempotency,
-- integration-only earnings, ratings.

DO $test$
DECLARE
  v_requester   bigint;
  v_worker_user bigint;
  v_worker2_user bigint;
  v_worker      bigint;
  v_worker2     bigint;
  v_skill       bigint;
  v_gig1        bigint;
  v_gig2        bigint;
  v_app1        bigint;
  v_app2        bigint;
  v_app_w2      bigint;
  v_asg1        bigint;
  v_asg2        bigint;
  v_day         timestamptz := date_trunc('day', now()) + interval '2 days';
  v_gig_cols    text := 'requester_app_user_id, gig_title, gig_description, skill_id, window_start, window_end, pricing_model_code, currency_code';
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'host@events.example') RETURNING id INTO v_requester;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'kavya.photo@example.com') RETURNING id INTO v_worker_user;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'sam.photo@example.com') RETURNING id INTO v_worker2_user;
  SELECT id INTO v_skill FROM ref.skill WHERE skill_name = 'Customer Service';

  PERFORM set_config('app.current_user_id', v_worker_user::text, true);
  INSERT INTO gig.gig_worker_profile (app_user_id, headline) VALUES (v_worker_user, 'Event host and coordinator') RETURNING id INTO v_worker;
  PERFORM set_config('app.current_user_id', v_worker2_user::text, true);
  INSERT INTO gig.gig_worker_profile (app_user_id, headline) VALUES (v_worker2_user, 'Weekend event staff') RETURNING id INTO v_worker2;

  -- worker calendar
  INSERT INTO gig.gig_availability (gig_worker_profile_id, available_from, available_to) VALUES (v_worker2, v_day, v_day + interval '8 hours');
  PERFORM qa.expect_error('overlapping availability slots for one worker',
    format('INSERT INTO gig.gig_availability (gig_worker_profile_id, available_from, available_to) VALUES (%s, %L, %L)',
           v_worker2, v_day + interval '4 hours', v_day + interval '10 hours'),
    'ex_gig_availability_no_overlap');

  -- gig requests: window and pricing rules
  PERFORM set_config('app.current_user_id', v_requester::text, true);
  PERFORM qa.expect_error('gig window that ends before it starts',
    format('INSERT INTO gig.gig_request (%s, fixed_price_amount) VALUES (%s, %L, %L, %s, %L, %L, %L, %L, 5000)',
           v_gig_cols, v_requester, 'Host', 'Host an event', v_skill, v_day + interval '5 hours', v_day, 'fixed', 'INR'),
    'ck_gig_request_window');
  PERFORM qa.expect_error('fixed-price gig that also carries a rate',
    format('INSERT INTO gig.gig_request (%s, fixed_price_amount, rate_amount, rate_unit_code) VALUES (%s, %L, %L, %s, %L, %L, %L, %L, 5000, 500, %L)',
           v_gig_cols, v_requester, 'Host', 'Host an event', v_skill, v_day, v_day + interval '4 hours', 'fixed', 'INR', 'hour'),
    'ck_gig_request_pricing');
  PERFORM qa.expect_error('rate-based gig without a unit',
    format('INSERT INTO gig.gig_request (%s, rate_amount) VALUES (%s, %L, %L, %s, %L, %L, %L, %L, 500)',
           v_gig_cols, v_requester, 'Host', 'Host an event', v_skill, v_day, v_day + interval '4 hours', 'rate', 'INR'),
    'ck_gig_request_pricing');
  INSERT INTO gig.gig_request (requester_app_user_id, gig_title, gig_description, skill_id, window_start, window_end,
                               pricing_model_code, fixed_price_amount, currency_code, gig_request_status_code)
  VALUES (v_requester, 'Product launch host', 'Host a 4-hour launch event', v_skill, v_day + interval '10 hours', v_day + interval '14 hours',
          'fixed', 6000, 'INR', 'open') RETURNING id INTO v_gig1;
  INSERT INTO gig.gig_request (requester_app_user_id, gig_title, gig_description, skill_id, window_start, window_end,
                               pricing_model_code, rate_amount, rate_unit_code, currency_code, gig_request_status_code)
  VALUES (v_requester, 'Expo booth staff', 'Staff an expo booth', v_skill, v_day + interval '12 hours', v_day + interval '16 hours',
          'rate', 800, 'hour', 'INR', 'open') RETURNING id INTO v_gig2;

  -- applications: workers apply, only the requester decides
  PERFORM set_config('app.current_user_id', v_worker_user::text, true);
  INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id) VALUES (v_gig1, v_worker) RETURNING id INTO v_app1;
  INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id) VALUES (v_gig2, v_worker) RETURNING id INTO v_app2;
  PERFORM qa.expect_error('applying twice to the same gig',
    format('INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id) VALUES (%s, %s)', v_gig1, v_worker),
    'uq_gig_application_gig_request_id_gig_worker_profile_id');
  PERFORM qa.expect_error('the worker accepting their own application (bids do not flow both ways)',
    format('UPDATE gig.gig_application SET gig_application_status_code = %L, decided_at = now() WHERE id = %s', 'accepted', v_app1),
    'trg_gig_application_decision');
  PERFORM set_config('app.current_user_id', v_worker2_user::text, true);
  INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id) VALUES (v_gig1, v_worker2) RETURNING id INTO v_app_w2;

  PERFORM set_config('app.current_user_id', v_requester::text, true);
  UPDATE gig.gig_application SET gig_application_status_code = 'accepted', decided_at = now() WHERE id IN (v_app1, v_app2);
  PERFORM qa.expect_error('assignment for an application that was not accepted',
    format('INSERT INTO gig.gig_assignment (gig_application_id, gig_request_id, gig_worker_profile_id, window_start, window_end) '
           || 'VALUES (%s, %s, %s, %L, %L)', v_app_w2, v_gig1, v_worker2, v_day + interval '10 hours', v_day + interval '14 hours'),
    'trg_gig_assignment_accepted');
  PERFORM qa.expect_error('assignment whose worker is not the applicant (composite FK)',
    format('INSERT INTO gig.gig_assignment (gig_application_id, gig_request_id, gig_worker_profile_id, window_start, window_end) '
           || 'VALUES (%s, %s, %s, %L, %L)', v_app1, v_gig1, v_worker2, v_day + interval '10 hours', v_day + interval '14 hours'),
    'fk_gig_assignment_application');

  -- B35: no overlapping live assignments for one worker
  INSERT INTO gig.gig_assignment (gig_application_id, gig_request_id, gig_worker_profile_id, window_start, window_end)
  VALUES (v_app1, v_gig1, v_worker, v_day + interval '10 hours', v_day + interval '14 hours') RETURNING id INTO v_asg1;
  PERFORM qa.expect_error('overlapping active assignments for one worker',
    format('INSERT INTO gig.gig_assignment (gig_application_id, gig_request_id, gig_worker_profile_id, window_start, window_end) '
           || 'VALUES (%s, %s, %s, %L, %L)', v_app2, v_gig2, v_worker, v_day + interval '12 hours', v_day + interval '16 hours'),
    'ex_gig_assignment_worker_window');
  UPDATE gig.gig_assignment SET gig_assignment_status_code = 'cancelled' WHERE id = v_asg1;
  PERFORM qa.expect_ok('the same overlap once the first assignment is cancelled',
    format('INSERT INTO gig.gig_assignment (gig_application_id, gig_request_id, gig_worker_profile_id, window_start, window_end) '
           || 'VALUES (%s, %s, %s, %L, %L)', v_app2, v_gig2, v_worker, v_day + interval '12 hours', v_day + interval '16 hours'));
  SELECT id INTO v_asg2 FROM gig.gig_assignment WHERE gig_application_id = v_app2;
  PERFORM qa.expect_error('reactivating the cancelled assignment now overlaps',
    format('UPDATE gig.gig_assignment SET gig_assignment_status_code = %L WHERE id = %s', 'active', v_asg1),
    'ex_gig_assignment_worker_window');

  -- fulfilment handoff (external system) and idempotency
  INSERT INTO gig.gig_fulfilment_handoff (gig_assignment_id, idempotency_key) VALUES (v_asg2, 'handoff-7f3a');
  PERFORM qa.expect_error('duplicate handoff idempotency key',
    format('INSERT INTO gig.gig_fulfilment_handoff (gig_assignment_id, idempotency_key) VALUES (%s, %L)', v_asg1, 'handoff-7f3a'),
    'uq_gig_fulfilment_handoff_idempotency_key');
  PERFORM qa.expect_error('acknowledged without an external reference',
    format('UPDATE gig.gig_fulfilment_handoff SET handoff_status_code = %L, sent_at = now(), acknowledged_at = now() WHERE gig_assignment_id = %s',
           'acknowledged', v_asg2),
    'ck_gig_fulfilment_handoff_acknowledged');

  -- earnings: source of truth is external; the application can only read them
  PERFORM qa.assert('application role can read but not write earnings',
    has_table_privilege('talentra_app', 'gig.gig_earning_reference', 'SELECT')
    AND NOT has_table_privilege('talentra_app', 'gig.gig_earning_reference', 'INSERT'));
  PERFORM qa.assert('integration role can insert earnings but not update them',
    has_table_privilege('talentra_integration', 'gig.gig_earning_reference', 'INSERT')
    AND NOT has_table_privilege('talentra_integration', 'gig.gig_earning_reference', 'UPDATE'));
  INSERT INTO gig.gig_earning_reference (gig_assignment_id, earning_kind_code, earning_amount, currency_code, source_system, source_reference, as_of)
  VALUES (v_asg2, 'estimated', 3200, 'INR', 'fulfil-x', 'evt-1001', now());
  PERFORM qa.expect_error('replayed earnings event (idempotency)',
    format('INSERT INTO gig.gig_earning_reference (gig_assignment_id, earning_kind_code, earning_amount, currency_code, source_system, source_reference, as_of) '
           || 'VALUES (%s, %L, 3300, %L, %L, %L, now())', v_asg2, 'estimated', 'INR', 'fulfil-x', 'evt-1001'),
    'uq_gig_earning_reference_source');
  PERFORM qa.expect_error('earnings rows cannot be edited',
    format('UPDATE gig.gig_earning_reference SET earning_amount = 1 WHERE gig_assignment_id = %s', v_asg2), 'forbid_update_delete');

  -- ratings
  PERFORM qa.expect_error('rating an assignment that is not completed',
    format('INSERT INTO gig.gig_rating (gig_assignment_id, rating_score) VALUES (%s, 5)', v_asg2), 'trg_gig_rating_completed_assignment');
  UPDATE gig.gig_assignment SET gig_assignment_status_code = 'completed', completed_at = now() WHERE id = v_asg2;
  PERFORM qa.expect_error('rating of 6',
    format('INSERT INTO gig.gig_rating (gig_assignment_id, rating_score) VALUES (%s, 6)', v_asg2), 'ck_gig_rating_rating_score');
  PERFORM qa.expect_ok('requester rates the completed gig',
    format('INSERT INTO gig.gig_rating (gig_assignment_id, rating_score, review_text) VALUES (%s, 5, %L)', v_asg2, 'Excellent host'));
  PERFORM qa.expect_error('second rating for the same assignment',
    format('INSERT INTO gig.gig_rating (gig_assignment_id, rating_score) VALUES (%s, 4)', v_asg2), 'uq_gig_rating_gig_assignment_id');

  -- blacklist: a blacklisted worker cannot apply to this requester's gigs
  INSERT INTO gig.gig_requester_worker_list (requester_app_user_id, gig_worker_profile_id, worker_list_kind_code)
  VALUES (v_requester, v_worker2, 'blacklist');
  PERFORM set_config('app.current_user_id', v_worker2_user::text, true);
  PERFORM qa.expect_error('blacklisted worker applying',
    format('INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id) VALUES (%s, %s)', v_gig2, v_worker2),
    'trg_gig_application_blacklist');
END
$test$;
