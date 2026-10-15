-- M14 gate, Sourcing and consultant requests (B46).

DO $test$
DECLARE
  v_employer    bigint;
  v_consultant  bigint;
  v_not_cons    bigint;
  v_cand_user   bigint;
  v_cand2_user  bigint;
  v_org         bigint;
  v_role        bigint;
  v_profile     bigint;
  v_profile2    bigint;
  v_job_open    bigint;
  v_job_closed  bigint;
  v_job_other   bigint;
  v_req         bigint;
  v_req2        bigint;
  v_shortlist   bigint;
  v_other_sl    bigint;
  v_batch       bigint;
  v_cols        text := 'organisation_id, posted_by_app_user_id, job_title, description, job_category_code, employment_type_code, work_type_code, job_role_id';
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO org.organisation (organisation_name) VALUES ('Acme Staffing') RETURNING id INTO v_org;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'hiring@acme.example') RETURNING id INTO v_employer;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'neha.consultant@example.com') RETURNING id INTO v_consultant;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'not.a.consultant@example.com') RETURNING id INTO v_not_cons;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'karthik@example.com') RETURNING id INTO v_cand_user;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'divya@example.com') RETURNING id INTO v_cand2_user;
  INSERT INTO admin.user_role (app_user_id, app_role_code, organisation_id) VALUES (v_employer, 'employer', v_org);
  INSERT INTO admin.user_role (app_user_id, app_role_code) VALUES (v_consultant, 'consultant');
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_cand_user, 'Karthik S') RETURNING id INTO v_profile;
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_cand2_user, 'Divya R') RETURNING id INTO v_profile2;
  SELECT id INTO v_role FROM ref.job_role WHERE role_name = 'Data Analyst';

  EXECUTE format('INSERT INTO job.job_requirement (%s, is_open_to_consultant, consultant_fee_pct) VALUES (%s, %s, %L, %L, %L, %L, %L, %s, true, 8.33) RETURNING id',
                 v_cols, v_org, v_employer, 'Data Analyst', 'SQL and dashboards', 'permanent', 'permanent', 'hybrid', v_role) INTO v_job_open;
  EXECUTE format('INSERT INTO job.job_requirement (%s) VALUES (%s, %s, %L, %L, %L, %L, %L, %s) RETURNING id',
                 v_cols, v_org, v_employer, 'Data Engineer', 'Pipelines', 'permanent', 'permanent', 'hybrid', v_role) INTO v_job_closed;
  EXECUTE format('INSERT INTO job.job_requirement (%s, is_open_to_consultant, consultant_fee_pct) VALUES (%s, %s, %L, %L, %L, %L, %L, %s, true, 5) RETURNING id',
                 v_cols, v_org, v_employer, 'BI Analyst', 'Reports', 'permanent', 'permanent', 'hybrid', v_role) INTO v_job_other;

  -- B46: consultants act only on jobs open to consultants
  PERFORM set_config('app.current_user_id', v_consultant::text, true);
  PERFORM qa.expect_error('consultant request on a job not open to consultants',
    format('INSERT INTO src.sourcing_request (job_requirement_id, consultant_app_user_id) VALUES (%s, %s)', v_job_closed, v_consultant),
    'trg_sourcing_request_consultant_open');
  PERFORM qa.expect_ok('the same request on a job open to consultants',
    format('INSERT INTO src.sourcing_request (job_requirement_id, consultant_app_user_id) VALUES (%s, %s)', v_job_open, v_consultant));
  SELECT id INTO v_req FROM src.sourcing_request WHERE job_requirement_id = v_job_open;
  PERFORM qa.expect_error('a user without the consultant role cannot request',
    format('INSERT INTO src.sourcing_request (job_requirement_id, consultant_app_user_id) VALUES (%s, %s)', v_job_open, v_not_cons),
    'trg_sourcing_request_consultant_open');
  PERFORM qa.expect_error('a second live request by the same consultant for the same job',
    format('INSERT INTO src.sourcing_request (job_requirement_id, consultant_app_user_id) VALUES (%s, %s)', v_job_open, v_consultant),
    'uq_sourcing_request_live_per_consultant');

  -- decisions
  PERFORM qa.expect_error('declined without a reason',
    format('UPDATE src.sourcing_request SET sourcing_request_status_code = %L, decided_by_app_user_id = %s, decided_at = now() WHERE id = %s',
           'declined', v_employer, v_req),
    'ck_sourcing_request_decline_reason');
  PERFORM qa.expect_error('accepted without recording who decided',
    format('UPDATE src.sourcing_request SET sourcing_request_status_code = %L WHERE id = %s', 'accepted', v_req),
    'ck_sourcing_request_decision');
  PERFORM qa.expect_error('the consultant cannot accept their own request',
    format('UPDATE src.sourcing_request SET sourcing_request_status_code = %L, decided_by_app_user_id = %s, decided_at = now() WHERE id = %s',
           'accepted', v_consultant, v_req),
    'trg_sourcing_request_consultant_open');
  PERFORM qa.expect_ok('the employer accepts',
    format('UPDATE src.sourcing_request SET sourcing_request_status_code = %L, decided_by_app_user_id = %s, decided_at = now() WHERE id = %s',
           'accepted', v_employer, v_req));

  -- sourcing shortlist reuses job.shortlist and must be for the same job
  INSERT INTO job.shortlist (organisation_id, owner_app_user_id, job_requirement_id, shortlist_name)
  VALUES (v_org, v_employer, v_job_open, 'Consultant picks') RETURNING id INTO v_shortlist;
  INSERT INTO job.shortlist (organisation_id, owner_app_user_id, job_requirement_id, shortlist_name)
  VALUES (v_org, v_employer, v_job_other, 'BI picks') RETURNING id INTO v_other_sl;
  PERFORM qa.expect_ok('link the sourcing request to its job shortlist',
    format('INSERT INTO src.sourcing_shortlist (sourcing_request_id, shortlist_id, job_requirement_id) VALUES (%s, %s, %s)', v_req, v_shortlist, v_job_open));
  PERFORM qa.expect_error('link it to a shortlist of another job',
    format('INSERT INTO src.sourcing_shortlist (sourcing_request_id, shortlist_id, job_requirement_id) VALUES (%s, %s, %s)', v_req, v_other_sl, v_job_open),
    'fk_sourcing_shortlist_shortlist_job');

  -- bulk outreach
  INSERT INTO src.outreach_batch (sender_app_user_id, job_requirement_id, sourcing_request_id, outreach_channel_code, message_template_key, idempotency_key)
  VALUES (v_consultant, v_job_open, v_req, 'email', 'outreach.job_invite', 'batch-001') RETURNING id INTO v_batch;
  PERFORM qa.expect_error('duplicate batch idempotency key',
    format('INSERT INTO src.outreach_batch (sender_app_user_id, outreach_channel_code, message_template_key, idempotency_key) VALUES (%s, %L, %L, %L)',
           v_consultant, 'email', 'outreach.job_invite', 'batch-001'),
    'uq_outreach_batch_idempotency_key');
  INSERT INTO src.outreach_recipient (outreach_batch_id, candidate_profile_id) VALUES (v_batch, v_profile);
  PERFORM qa.expect_error('same candidate twice in one batch',
    format('INSERT INTO src.outreach_recipient (outreach_batch_id, candidate_profile_id) VALUES (%s, %s)', v_batch, v_profile),
    'uq_outreach_recipient_batch_candidate');

  -- a candidate who blocked the sender cannot be contacted
  PERFORM set_config('app.current_user_id', v_cand2_user::text, true);
  INSERT INTO admin.block_list (blocker_app_user_id, blocked_app_user_id) VALUES (v_cand2_user, v_consultant);
  PERFORM set_config('app.current_user_id', v_consultant::text, true);
  PERFORM qa.expect_error('outreach to a candidate who blocked the sender',
    format('INSERT INTO src.outreach_recipient (outreach_batch_id, candidate_profile_id) VALUES (%s, %s)', v_batch, v_profile2),
    'trg_outreach_recipient_not_blocked');
  PERFORM set_config('app.current_user_id', v_cand_user::text, true);
  INSERT INTO admin.block_list (blocker_app_user_id, blocked_organisation_id) VALUES (v_cand_user, v_org);
  PERFORM set_config('app.current_user_id', v_employer::text, true);
  INSERT INTO src.outreach_batch (sender_app_user_id, sender_organisation_id, outreach_channel_code, message_template_key, idempotency_key)
  VALUES (v_employer, v_org, 'sms', 'outreach.job_invite', 'batch-002') RETURNING id INTO v_req2;
  PERFORM qa.expect_error('outreach from a company the candidate blocked',
    format('INSERT INTO src.outreach_recipient (outreach_batch_id, candidate_profile_id) VALUES (%s, %s)', v_req2, v_profile),
    'trg_outreach_recipient_not_blocked');
  PERFORM qa.expect_error('free-text message template key',
    format('INSERT INTO src.outreach_batch (sender_app_user_id, outreach_channel_code, message_template_key, idempotency_key) VALUES (%s, %L, %L, %L)',
           v_employer, 'email', 'Hi there, we have a job for you', 'batch-003'),
    'ck_outreach_batch_message_template_key_format');
END
$test$;
