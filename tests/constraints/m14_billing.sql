-- M14 gate, Subscriptions, wallet, payments and download history (B47, RG10).

DO $test$
DECLARE
  v_account    bigint;
  v_licence    bigint;
  v_plan       bigint;
  v_sub1       bigint;
  v_sub2       bigint;
  v_wallet     bigint;
  v_order      bigint;
  v_recruiter  bigint;
  v_cand_user  bigint;
  v_profile    bigint;
  v_recharge   bigint;
  v_debit      bigint;
  v_fix        bigint;
  v_download   bigint;
  v_balance    numeric;
BEGIN
  PERFORM set_config('app.current_user_id', '1', true);
  INSERT INTO org.account (account_name, account_status_code) VALUES ('Acme Staffing', 'active') RETURNING id INTO v_account;
  INSERT INTO lic.licence (account_id, licence_name, max_users, max_devices_per_user) VALUES (v_account, 'Acme Pro', 25, 3) RETURNING id INTO v_licence;
  SELECT id INTO v_plan FROM billing.plan WHERE code = 'recruiter_pro';
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'buyer@acme.example') RETURNING id INTO v_recruiter;
  INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'lakshmi@example.com') RETURNING id INTO v_cand_user;
  INSERT INTO profile.candidate_profile (app_user_id, full_name) VALUES (v_cand_user, 'Lakshmi N') RETURNING id INTO v_profile;

  -- RG10: subscription periods of one licence never overlap
  INSERT INTO billing.subscription (licence_id, plan_id, subscription_status_code, subscription_period, price_amount, price_currency_code)
  VALUES (v_licence, v_plan, 'active', daterange('2026-01-01', '2027-01-01'), 149999, 'INR') RETURNING id INTO v_sub1;
  PERFORM qa.expect_error('overlapping subscriptions on one licence',
    format('INSERT INTO billing.subscription (licence_id, plan_id, subscription_status_code, subscription_period, price_amount, price_currency_code) '
           || 'VALUES (%s, %s, %L, daterange(%L, %L), 149999, %L)', v_licence, v_plan, 'active', '2026-10-01', '2027-10-01', 'INR'),
    'ex_subscription_licence_period');
  INSERT INTO billing.subscription_cancellation (subscription_id, cancellation_reason, effective_on)
  VALUES (v_sub1, 'Upgrading mid-term', '2026-10-01');
  PERFORM qa.assert_equals('cancellation marks the subscription cancelled',
    (SELECT subscription_status_code::text FROM billing.subscription WHERE id = v_sub1), 'cancelled');
  PERFORM qa.expect_ok('the same overlap once the first subscription is cancelled',
    format('INSERT INTO billing.subscription (licence_id, plan_id, subscription_status_code, subscription_period, price_amount, price_currency_code) '
           || 'VALUES (%s, %s, %L, daterange(%L, %L), 149999, %L)', v_licence, v_plan, 'active', '2026-10-01', '2027-10-01', 'INR'));
  SELECT id INTO v_sub2 FROM billing.subscription WHERE licence_id = v_licence AND subscription_status_code = 'active';
  PERFORM qa.expect_error('a subscription period without an end date',
    format('INSERT INTO billing.subscription (licence_id, plan_id, subscription_period, price_amount, price_currency_code) '
           || 'VALUES (%s, %s, daterange(%L, NULL), 0, %L)', v_licence, v_plan, '2028-01-01', 'INR'),
    'ck_subscription_period');

  -- payments: idempotent webhooks move the order status
  INSERT INTO billing.wallet (account_id, currency_code) VALUES (v_account, 'INR') RETURNING id INTO v_wallet;
  INSERT INTO billing.payment_order (account_id, wallet_id, order_amount, order_currency_code, payment_gateway_code, idempotency_key, gateway_order_token)
  VALUES (v_account, v_wallet, 10000, 'INR', 'razorpay', 'checkout-001', 'order_Nq8x1') RETURNING id INTO v_order;
  INSERT INTO billing.payment_event (payment_order_id, payment_gateway_code, gateway_event_id, payment_status_code, event_amount, event_currency_code)
  VALUES (v_order, 'razorpay', 'evt_001', 'captured', 10000, 'INR');
  PERFORM qa.assert_equals('a captured webhook moves the order to captured',
    (SELECT payment_status_code::text FROM billing.payment_order WHERE id = v_order), 'captured');
  PERFORM qa.expect_error('the same webhook delivered twice',
    format('INSERT INTO billing.payment_event (payment_order_id, payment_gateway_code, gateway_event_id, payment_status_code) VALUES (%s, %L, %L, %L)',
           v_order, 'razorpay', 'evt_001', 'captured'),
    'uq_payment_event_gateway_event');
  PERFORM qa.expect_error('a payment order for both a subscription and a wallet',
    format('INSERT INTO billing.payment_order (account_id, subscription_id, wallet_id, order_amount, order_currency_code, payment_gateway_code, idempotency_key) '
           || 'VALUES (%s, %s, %s, 1, %L, %L, %L)', v_account, v_sub2, v_wallet, 'INR', 'razorpay', 'checkout-002'),
    'ck_payment_order_single_purpose');

  -- wallet ledger: posted through the locking API, append-only, never negative
  v_recharge := billing.post_ledger_entry(v_wallet, 'recharge', 10000, 'recharge-001', NULL, v_order);
  PERFORM qa.assert_equals('posting the same key again is idempotent (same entry)',
    billing.post_ledger_entry(v_wallet, 'recharge', 10000, 'recharge-001', NULL, v_order), v_recharge);
  v_debit := billing.post_ledger_entry(v_wallet, 'consumption', -2500, 'post-job-001');
  PERFORM qa.assert_equals('balance after recharge and one debit', (SELECT balance FROM billing.wallet WHERE id = v_wallet), 7500.00::d_money);
  PERFORM qa.expect_error('debit that would make the balance negative',
    format('SELECT billing.post_ledger_entry(%s, %L, -9000, %L)', v_wallet, 'consumption', 'post-job-002'),
    'ck_wallet_balance_non_negative');
  PERFORM qa.expect_error('UPDATE of a ledger row',
    format('UPDATE billing.wallet_ledger_entry SET amount = -1 WHERE id = %s', v_debit), 'forbid_update_delete');
  PERFORM qa.expect_error('DELETE of a ledger row',
    format('DELETE FROM billing.wallet_ledger_entry WHERE id = %s', v_debit), 'forbid_update_delete');
  v_fix := billing.post_ledger_entry(v_wallet, 'correction', 0, 'fix-001', v_debit);
  PERFORM qa.assert_equals('a correction reverses the original amount exactly',
    (SELECT amount FROM billing.wallet_ledger_entry WHERE id = v_fix), 2500.00::d_money);
  SELECT balance INTO v_balance FROM billing.wallet WHERE id = v_wallet;
  PERFORM qa.assert('balance reconciles with the ledger (sum of entries = balance = last balance_after)',
    v_balance = (SELECT sum(amount) FROM billing.wallet_ledger_entry WHERE wallet_id = v_wallet)
    AND v_balance = (SELECT balance_after FROM billing.wallet_ledger_entry WHERE id = v_fix) AND v_balance = 10000);
  PERFORM qa.expect_error('reversing the same entry twice',
    format('SELECT billing.post_ledger_entry(%s, %L, 0, %L, %s)', v_wallet, 'correction', 'fix-002', v_debit),
    'uq_wallet_ledger_entry_reverses_wallet_ledger_entry_id');
  PERFORM qa.expect_error('a recharge entry with the wrong sign',
    format('SELECT billing.post_ledger_entry(%s, %L, -5, %L, NULL, %s)', v_wallet, 'recharge', 'bad-001', v_order),
    'ck_wallet_ledger_entry_sign');
  PERFORM qa.assert('application role cannot write the wallet or ledger directly',
    NOT has_table_privilege('talentra_app', 'billing.wallet', 'UPDATE')
    AND NOT has_table_privilege('talentra_app', 'billing.wallet_ledger_entry', 'INSERT'));

  -- refunds never exceed the payment
  INSERT INTO billing.refund (payment_order_id, refund_amount, refund_currency_code, refund_reason) VALUES (v_order, 4000, 'INR', 'Partial refund');
  PERFORM qa.expect_error('refunds larger than the payment',
    format('INSERT INTO billing.refund (payment_order_id, refund_amount, refund_currency_code, refund_reason) VALUES (%s, 6001, %L, %L)',
           v_order, 'INR', 'Too much'),
    'trg_refund_within_payment');
  PERFORM qa.expect_ok('a refund up to the remaining amount',
    format('INSERT INTO billing.refund (payment_order_id, refund_amount, refund_currency_code, refund_reason) VALUES (%s, 6000, %L, %L)',
           v_order, 'INR', 'Rest'));

  -- download history references its ledger debit
  PERFORM set_config('app.current_user_id', v_recruiter::text, true);
  v_download := billing.record_profile_download(v_profile, v_wallet, 150, 'download-001');
  PERFORM qa.assert('download event, consumption and audit written together',
    EXISTS (SELECT 1 FROM billing.profile_download_event d
              JOIN billing.wallet_ledger_entry e ON e.id = d.wallet_ledger_entry_id AND e.amount = -150
              JOIN billing.credit_consumption c ON c.wallet_ledger_entry_id = e.id AND c.consumption_purpose_code = 'profile_download'
             WHERE d.id = v_download AND d.downloader_app_user_id = v_recruiter)
    AND EXISTS (SELECT 1 FROM audit.audit_event WHERE audit_action_code = 'profile_downloaded' AND subject_id = v_profile));
  PERFORM qa.assert_equals('a retried download call does not charge twice',
    billing.record_profile_download(v_profile, v_wallet, 150, 'download-001'), v_download);
  PERFORM qa.expect_error('a download without a ledger entry',
    format('INSERT INTO billing.profile_download_event (candidate_profile_id, downloader_app_user_id) VALUES (%s, %s)', v_profile, v_recruiter),
    'wallet_ledger_entry_id');
  PERFORM qa.expect_error('a download pointing at a credit instead of a debit',
    format('INSERT INTO billing.profile_download_event (candidate_profile_id, downloader_app_user_id, wallet_ledger_entry_id) VALUES (%s, %s, %s)',
           v_profile, v_recruiter, v_fix),
    'trg_profile_download_event_debit');
  PERFORM qa.expect_error('download history rows cannot be edited',
    format('UPDATE billing.profile_download_event SET downloaded_at = now() WHERE id = %s', v_download), 'forbid_update_delete');
END
$test$;
