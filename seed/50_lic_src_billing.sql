-- M19 seed, step 5 (Licences, Sourcing, Subscriptions): licences and seats, devices and sessions, blocking, sourcing
-- requests, outreach, plans bought, payments, refunds, wallets with a reconciling ledger, downloads.
\ir _preamble.sql

-- ---------------------------------------------------------------------------------------------------
-- Licences: one per account; recruiters hold the seats; sessions stay within the per-user device limit
INSERT INTO lic.licence (id, account_id, licence_name, max_users, max_devices_per_user, licence_status_code, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT a.id, a.id, a.account_name || ' licence', 5, 2 + (a.id % 2),
       CASE WHEN a.account_status_code IN ('suspended', 'closed') THEN 'suspended' ELSE 'active' END, a.created_at, a.created_at
  FROM org.account a;

INSERT INTO lic.licence_seat (licence_id, app_user_id, assigned_at, created_at, updated_at)
SELECT ((k - 1) % p.n_hiring) + 1, p.u_rec + k, now() - make_interval(days => 20 + (seed.h(k, 400) * 400)::int), now(), now()
  FROM seed.params p, generate_series(1, (SELECT n_rec FROM seed.params)) k;

INSERT INTO lic.registered_device (app_user_id, device_fingerprint_hash, device_platform_code, device_label, first_seen_at, last_seen_at,
                                   revoked_at, created_at, updated_at)
SELECT p.u_rec + k, digest('dev-' || (p.u_rec + k) || '-' || j, 'sha256'), (ARRAY['web','android','ios','desktop'])[1 + (k + j) % 4],
       'Device ' || j, now() - interval '100 days', now() - make_interval(days => (seed.h(k * 3 + j, 401) * 60)::int),
       CASE WHEN j = 2 AND seed.h(k, 402) < 0.05 THEN now() - interval '10 days' END, now(), now()
  FROM seed.params p, generate_series(1, (SELECT n_rec FROM seed.params)) k, generate_series(1, 2) j
 WHERE j = 1 OR seed.h(k, 403) < 0.6;

-- ended sessions (history) and open sessions (within the licence's device limit)
INSERT INTO lic.login_session (app_user_id, registered_device_id, licence_seat_id, session_token_hash, started_at, last_activity_at,
                               expires_at, ended_at, session_end_reason_code, created_at, updated_at)
SELECT d.app_user_id, d.id, s.id, digest('hist-' || d.id || '-' || h, 'sha256'),
       now() - make_interval(days => 5 + h * 3), now() - make_interval(days => 5 + h * 3) + interval '2 hours',
       now() - make_interval(days => 5 + h * 3) + interval '12 hours', now() - make_interval(days => 5 + h * 3) + interval '3 hours',
       (ARRAY['logout','idle_timeout','expired'])[1 + (d.id + h) % 3], now(), now()
  FROM lic.registered_device d JOIN lic.licence_seat s ON s.app_user_id = d.app_user_id AND s.released_at IS NULL
  CROSS JOIN generate_series(1, 3) h;

INSERT INTO lic.login_session (app_user_id, registered_device_id, licence_seat_id, session_token_hash, started_at, last_activity_at,
                               expires_at, created_at, updated_at)
SELECT d.app_user_id, d.id, s.id, digest('open-' || d.id, 'sha256'), now() - interval '1 hour', now() - interval '5 minutes',
       now() + interval '11 hours', now(), now()
  FROM lic.registered_device d JOIN lic.licence_seat s ON s.app_user_id = d.app_user_id AND s.released_at IS NULL
 WHERE d.revoked_at IS NULL AND seed.h(d.id, 404) < 0.5;

INSERT INTO lic.login_attempt (app_user_id, registered_device_id, login_outcome_code, client_ip_masked, attempted_at, created_at)
SELECT d.app_user_id, d.id, 'started', '198.51.100.x', now() - make_interval(hours => (seed.h(d.id, 405) * 700)::int), now()
  FROM lic.registered_device d;
INSERT INTO lic.login_attempt (app_user_id, registered_device_id, login_outcome_code, client_ip_masked, attempt_detail, attempted_at, created_at)
SELECT d.app_user_id, d.id, 'device_limit', '198.51.100.x', '{"limit": 2, "active": 2}'::jsonb,
       now() - make_interval(hours => (seed.h(d.id, 406) * 700)::int), now()
  FROM lic.registered_device d WHERE seed.h(d.id, 406) < 0.03;
INSERT INTO audit.audit_event (actor_app_user_id, audit_action_code, subject_table, subject_id, event_detail, occurred_at, created_at)
SELECT a.app_user_id, 'device_limit_exceeded', 'lic.licence_seat', s.id, a.attempt_detail || jsonb_build_object('app_user_id', a.app_user_id),
       a.attempted_at, a.attempted_at
  FROM lic.login_attempt a JOIN lic.licence_seat s ON s.app_user_id = a.app_user_id AND s.released_at IS NULL
 WHERE a.login_outcome_code = 'device_limit';

INSERT INTO lic.session_revocation (login_session_id, revocation_reason, revoked_at, created_at)
SELECT id, 'Revoked by administrator', ended_at, ended_at FROM lic.login_session WHERE session_end_reason_code = 'expired' AND id % 25 = 0;
UPDATE lic.login_session SET session_end_reason_code = 'revoked'
 WHERE id IN (SELECT login_session_id FROM lic.session_revocation);

-- ---------------------------------------------------------------------------------------------------
-- Blocking: 2% of candidates block one organisation (their own history of the company that contacted them)
INSERT INTO admin.block_list (blocker_app_user_id, blocked_organisation_id, block_reason, created_at, updated_at)
SELECT p.u_cand + c, 1 + floor(seed.h(c, 410) * p.n_hiring)::bigint, CASE WHEN c % 3 = 0 THEN 'Too many messages' END,
       now() - make_interval(days => (seed.h(c, 411) * 300)::int), now()
  FROM seed.params p, generate_series(1, (SELECT n_cand FROM seed.params)) c WHERE seed.h(c, 412) < 0.02;

-- ---------------------------------------------------------------------------------------------------
-- Sourcing: consultants request jobs open to consultants; employers decide
CREATE TEMP TABLE tmp_consult_jobs AS
SELECT row_number() OVER (ORDER BY id) AS rn, id, organisation_id
  FROM job.job_requirement WHERE is_open_to_consultant AND job_requirement_status_code = 'open';
SELECT count(*) AS consult_jobs FROM tmp_consult_jobs \gset

INSERT INTO src.sourcing_request (job_requirement_id, consultant_app_user_id, consultant_organisation_id, sourcing_request_status_code,
                                  request_note, requested_at, decided_by_app_user_id, decided_at, decline_reason, created_at, updated_at)
SELECT cj.id, p.u_consult + c.k, CASE WHEN c.k % 2 = 0 THEN p.n_hiring + 1 + (c.k % greatest(1, p.n_org - p.n_hiring)) END,
       s.status, 'We have a strong pool for this role.', t.requested_at,
       CASE WHEN s.status IN ('accepted', 'declined') THEN p.u_rec + cj.organisation_id END,
       CASE WHEN s.status IN ('accepted', 'declined') THEN t.requested_at + interval '2 days' END,
       CASE WHEN s.status = 'declined' THEN 'Role already assigned to another agency' END,
       t.requested_at, t.requested_at
  FROM seed.params p
  CROSS JOIN LATERAL generate_series(1, p.n_consult) c(k)
  CROSS JOIN generate_series(1, 10) q
  JOIN tmp_consult_jobs cj ON cj.rn = 1 + ((c.k * 31 + q * 7) % GREATEST(1, (SELECT count(*) FROM tmp_consult_jobs)))
  CROSS JOIN LATERAL (SELECT (ARRAY['requested','accepted','accepted','accepted','declined','declined','withdrawn'])
                              [1 + ((c.k + q) % 7)] AS status) s
  CROSS JOIN LATERAL (SELECT now() - make_interval(days => 3 + ((c.k * 13 + q * 5) % 300)::int) AS requested_at) t
 WHERE (SELECT count(*) FROM tmp_consult_jobs) > 0
ON CONFLICT DO NOTHING;

INSERT INTO src.sourcing_shortlist (sourcing_request_id, shortlist_id, job_requirement_id, created_at, updated_at)
SELECT sr.id, sl.id, sr.job_requirement_id, sr.created_at, sr.created_at
  FROM src.sourcing_request sr JOIN job.shortlist sl ON sl.job_requirement_id = sr.job_requirement_id
 WHERE sr.sourcing_request_status_code = 'accepted';

-- bulk outreach: employers and accepted consultants; candidates who blocked the sender's organisation are never included
INSERT INTO src.outreach_batch (sender_app_user_id, sender_organisation_id, job_requirement_id, sourcing_request_id, outreach_channel_code,
                                message_template_key, idempotency_key, requested_at, created_at, updated_at)
SELECT p.u_rec + 1 + (b % p.n_rec), 1 + (b % p.n_rec) % p.n_hiring, NULL, NULL,
       (ARRAY['email','sms','whatsapp','in_app'])[1 + b % 4], 'enum.outreach_channel.email', 'seed-batch-' || b,
       now() - make_interval(days => (seed.h(b, 420) * 300)::int), now(), now()
  FROM seed.params p, generate_series(1, (SELECT greatest(10, n_cand / 400) FROM seed.params)) b;

INSERT INTO src.outreach_recipient (outreach_batch_id, candidate_profile_id, outreach_recipient_status_code, provider_message_reference,
                                    sent_at, delivered_at, created_at, updated_at)
SELECT ob.id, cand, st.status, CASE WHEN st.sent THEN 'seed-msg-' || ob.id || '-' || k END,
       CASE WHEN st.sent THEN ob.requested_at + interval '1 minute' END,
       CASE WHEN st.status IN ('delivered', 'replied') THEN ob.requested_at + interval '2 minutes' END,
       ob.requested_at, ob.requested_at
  FROM src.outreach_batch ob CROSS JOIN seed.params p CROSS JOIN generate_series(1, 40) k
  CROSS JOIN LATERAL (SELECT 1 + ((ob.id * 37 + k * 101) % p.n_cand) AS cand) c
  CROSS JOIN LATERAL (SELECT s AS status, s IN ('sent', 'delivered', 'replied') AS sent
                        FROM (SELECT (ARRAY['sent','delivered','delivered','replied','failed','queued'])[1 + ((ob.id + k) % 6)] AS s) x) st
 WHERE NOT EXISTS (SELECT 1 FROM admin.block_list b
                    WHERE b.blocker_app_user_id = p.u_cand + c.cand AND b.deleted_at IS NULL
                      AND (b.blocked_app_user_id = ob.sender_app_user_id OR b.blocked_organisation_id = ob.sender_organisation_id));

-- ---------------------------------------------------------------------------------------------------
-- Subscriptions: two consecutive periods per licence (the first renewed into the second); 5% of current ones cancelled
INSERT INTO billing.subscription (licence_id, plan_id, subscription_status_code, subscription_period, price_amount, price_currency_code,
                                  is_auto_renew, created_at, updated_at)
SELECT l.id, (SELECT id FROM billing.plan ORDER BY id OFFSET (l.id + k) % 2 LIMIT 1),
       CASE WHEN k = 1 THEN 'expired' WHEN l.id % 20 = 0 THEN 'cancelled' ELSE 'active' END,
       CASE WHEN k = 1 THEN daterange(date '2025-01-01', date '2026-01-01') ELSE daterange(date '2026-01-01', date '2027-01-01') END,
       CASE WHEN (l.id + k) % 2 = 0 THEN 149999 ELSE 4999 * 12 END, 'INR', true,
       CASE WHEN k = 1 THEN timestamptz '2025-01-01' ELSE timestamptz '2026-01-01' END, now()
  FROM lic.licence l CROSS JOIN generate_series(1, 2) k;

INSERT INTO billing.subscription_renewal (from_subscription_id, to_subscription_id, is_automatic, renewed_at, created_at, updated_at)
SELECT s1.id, s2.id, true, timestamptz '2026-01-01', now(), now()
  FROM billing.subscription s1 JOIN billing.subscription s2 ON s2.licence_id = s1.licence_id AND s2.id > s1.id
 WHERE s1.subscription_status_code = 'expired';
INSERT INTO billing.subscription_cancellation (subscription_id, cancellation_reason, effective_on, cancelled_at, created_at, updated_at)
SELECT id, 'Customer request', date '2026-06-01', timestamptz '2026-05-20', now(), now()
  FROM billing.subscription WHERE subscription_status_code = 'cancelled';

-- payments: one captured order and event and invoice per subscription (account of the licence)
INSERT INTO billing.payment_order (account_id, subscription_id, order_amount, order_currency_code, payment_gateway_code, idempotency_key,
                                   gateway_order_token, payment_status_code, created_at, updated_at)
SELECT l.account_id, s.id, s.price_amount, 'INR', 'razorpay', 'seed-sub-' || s.id, 'order_' || md5(s.id::text), 'captured',
       s.created_at, s.created_at
  FROM billing.subscription s JOIN lic.licence l ON l.id = s.licence_id;
INSERT INTO billing.payment_event (payment_order_id, payment_gateway_code, gateway_event_id, payment_status_code, event_amount,
                                   event_currency_code, received_at, created_at)
SELECT o.id, 'razorpay', 'seed-evt-sub-' || o.subscription_id, 'captured', o.order_amount, 'INR', o.created_at + interval '1 minute', o.created_at
  FROM billing.payment_order o WHERE o.subscription_id IS NOT NULL;
INSERT INTO billing.invoice (account_id, payment_order_id, invoice_number, invoice_status_code, issued_on, net_amount, tax_amount,
                             total_amount, currency_code, created_at, updated_at)
SELECT o.account_id, o.id, 'INV-' || to_char(o.created_at, 'YYYY') || '-' || lpad(o.id::text, 8, '0'), 'paid', o.created_at::date,
       round(o.order_amount / 1.18, 2), o.order_amount - round(o.order_amount / 1.18, 2), o.order_amount, 'INR', o.created_at, o.created_at
  FROM billing.payment_order o WHERE o.subscription_id IS NOT NULL;

-- wallets: three INR 10,000 recharges, some downloads and views, 2% with a refund; the ledger carries running balances
INSERT INTO billing.wallet (id, account_id, currency_code, balance, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT a.id, a.id, 'INR', 0, a.created_at, a.created_at FROM org.account a;

INSERT INTO billing.payment_order (account_id, wallet_id, order_amount, order_currency_code, payment_gateway_code, idempotency_key,
                                   gateway_order_token, payment_status_code, created_at, updated_at)
SELECT w.account_id, w.id, 10000, 'INR', 'razorpay', 'seed-recharge-' || w.id || '-' || k, 'order_' || md5('r' || w.id || '-' || k),
       CASE WHEN k = 1 AND w.id % 50 = 0 THEN 'partially_refunded' ELSE 'captured' END,
       w.created_at + make_interval(days => k), w.created_at + make_interval(days => k)
  FROM billing.wallet w CROSS JOIN generate_series(1, 3) k;
INSERT INTO billing.payment_event (payment_order_id, payment_gateway_code, gateway_event_id, payment_status_code, event_amount,
                                   event_currency_code, received_at, created_at)
SELECT o.id, 'razorpay', 'seed-evt-' || o.idempotency_key, 'captured', o.order_amount, 'INR', o.created_at + interval '1 minute', o.created_at
  FROM billing.payment_order o WHERE o.wallet_id IS NOT NULL;
INSERT INTO billing.invoice (account_id, payment_order_id, invoice_number, invoice_status_code, issued_on, net_amount, tax_amount,
                             total_amount, currency_code, created_at, updated_at)
SELECT o.account_id, o.id, 'INV-W-' || lpad(o.id::text, 9, '0'), 'paid', o.created_at::date, round(o.order_amount / 1.18, 2),
       o.order_amount - round(o.order_amount / 1.18, 2), o.order_amount, 'INR', o.created_at, o.created_at
  FROM billing.payment_order o WHERE o.wallet_id IS NOT NULL;
INSERT INTO billing.refund (payment_order_id, refund_amount, refund_currency_code, refund_status_code, refund_reason, gateway_refund_token,
                            requested_at, processed_at, created_at, updated_at)
SELECT o.id, 2000, 'INR', 'processed', 'Duplicate purchase', 'rfnd_' || md5(o.id::text), o.created_at + interval '2 days',
       o.created_at + interval '3 days', o.created_at, o.created_at
  FROM billing.payment_order o WHERE o.payment_status_code = 'partially_refunded';

-- ledger: recharges first, then one refund, then consumption; balance_after is the running sum (never negative)
CREATE UNLOGGED TABLE seed.ledger_plan AS
SELECT w.id AS wallet_id, e.kind, e.k, e.amount, e.ts, e.key
  FROM billing.wallet w
  CROSS JOIN LATERAL (
    SELECT 'recharge' AS kind, k, 10000::numeric AS amount, w.created_at + make_interval(days => k, hours => 1) AS ts,
           'seed-led-r-' || w.id || '-' || k AS key
      FROM generate_series(1, 3) k
    UNION ALL
    SELECT 'refund', 1, -2000::numeric, w.created_at + interval '6 days', 'seed-led-f-' || w.id WHERE w.id % 50 = 0
    UNION ALL
    SELECT 'consumption', i, -150::numeric, w.created_at + interval '10 days' + make_interval(hours => i::int), 'seed-led-c-' || w.id || '-' || i
      FROM generate_series(1, 60 + (w.id % 40)) i) e;

INSERT INTO billing.wallet_ledger_entry (wallet_id, ledger_entry_type_code, amount, currency_code, balance_after, payment_order_id, refund_id,
                                         idempotency_key, posted_at, created_at)
SELECT lp.wallet_id, lp.kind, lp.amount, 'INR',
       sum(lp.amount) OVER (PARTITION BY lp.wallet_id ORDER BY lp.ts, lp.k),
       CASE WHEN lp.kind = 'recharge' THEN o.id END,
       CASE WHEN lp.kind = 'refund' THEN rf.id END,
       lp.key, lp.ts, lp.ts
  FROM seed.ledger_plan lp
  LEFT JOIN billing.payment_order o ON o.idempotency_key = 'seed-recharge-' || lp.wallet_id || '-' || lp.k AND lp.kind = 'recharge'
  LEFT JOIN billing.refund rf ON rf.payment_order_id = (SELECT id FROM billing.payment_order WHERE idempotency_key = 'seed-recharge-' || lp.wallet_id || '-1')
                              AND lp.kind = 'refund'
 ORDER BY lp.ts, lp.wallet_id, lp.k;

UPDATE billing.wallet w SET balance = x.bal
  FROM (SELECT DISTINCT ON (wallet_id) wallet_id, balance_after AS bal FROM billing.wallet_ledger_entry ORDER BY wallet_id, posted_at DESC, id DESC) x
 WHERE x.wallet_id = w.id;

INSERT INTO billing.credit_consumption (wallet_ledger_entry_id, consumption_purpose_code, units, created_at)
SELECT e.id, CASE WHEN e.id % 10 = 0 THEN 'profile_view' ELSE 'profile_download' END, 1, e.posted_at
  FROM billing.wallet_ledger_entry e WHERE e.ledger_entry_type_code = 'consumption';

INSERT INTO billing.profile_download_event (candidate_profile_id, downloader_app_user_id, downloader_organisation_id, wallet_ledger_entry_id,
                                            downloaded_at, created_at)
SELECT 1 + ((e.wallet_id * 977 + e.id * 131) % p.n_cand), p.u_rec + e.wallet_id + p.n_hiring * (e.id % 2), e.wallet_id,
       e.id, e.posted_at, e.posted_at
  FROM billing.wallet_ledger_entry e CROSS JOIN seed.params p
  JOIN billing.credit_consumption c ON c.wallet_ledger_entry_id = e.id AND c.consumption_purpose_code = 'profile_download';

SELECT count(*) AS ledger_rows FROM billing.wallet_ledger_entry \gset
SELECT count(*) AS downloads FROM billing.profile_download_event \gset
SELECT count(*) AS sessions FROM lic.login_session \gset
\echo ledger=:ledger_rows downloads=:downloads sessions=:sessions
