-- M19 seed, step 6 (Notifications, community, support, audit trail).
\ir _preamble.sql

SELECT notif.ensure_delivery_partitions(date '2025-08-01', 20) AS partitions_created \gset
\echo delivery partitions created: :partitions_created

-- preferences (candidates); UI languages restricted to the supported ones
INSERT INTO notif.user_preference (app_user_id, ui_language_id, profile_visibility_code, show_salary_to_recruiters, allow_recruiter_contact,
                                   created_at, updated_at)
SELECT u.id, (SELECT id FROM ref.language WHERE code = (ARRAY['en','en','hi','ta'])[1 + u.id % 4]),
       (ARRAY['all_employers','all_employers','all_employers','applied_only','hidden'])[1 + u.id % 5],
       u.id % 7 = 0, u.id % 9 <> 0, u.created_at, u.created_at
  FROM admin.app_user u CROSS JOIN seed.params p
 WHERE u.id > p.u_cand AND u.id <= p.u_cand + p.n_cand AND seed.h(u.id, 500) < 0.30;

INSERT INTO notif.notification_preference (app_user_id, notification_event_type_code, notification_channel_code, is_enabled, created_at, updated_at)
SELECT u.id, (ARRAY['job_alert','recruiter_message','application_status'])[1 + u.id % 3],
       (ARRAY['sms','whatsapp','email','push'])[1 + u.id % 4], false, u.created_at, u.created_at
  FROM admin.app_user u CROSS JOIN seed.params p
 WHERE u.id > p.u_cand AND u.id <= p.u_cand + p.n_cand AND seed.h(u.id, 501) < 0.10;

INSERT INTO notif.job_alert (candidate_profile_id, saved_search_id, alert_frequency_code, notification_channel_code, is_active, last_sent_at,
                             created_at, updated_at)
SELECT ss.candidate_profile_id, ss.id, (ARRAY['instant','daily','daily','weekly'])[1 + ss.id % 4], 'email', ss.id % 10 <> 0,
       CASE WHEN ss.id % 3 = 0 THEN now() - interval '1 day' END, ss.created_at, ss.created_at
  FROM job.saved_search ss WHERE seed.h(ss.id, 502) < 0.5;

-- notifications and monthly-partitioned deliveries
INSERT INTO notif.notification (recipient_app_user_id, notification_event_type_code, message_label_key, message_parameters, read_at, created_at, updated_at)
SELECT p.u_cand + 1 + floor(seed.h(v, 510) * p.n_cand)::bigint, e.code, 'enum.notification_event_type.' || e.code,
       jsonb_build_object('ref', v), CASE WHEN seed.h(v, 511) < 0.5 THEN t.at + interval '2 hours' END, t.at, t.at
  FROM seed.params p, generate_series(1, (SELECT n_cand FROM seed.params)) v
  CROSS JOIN LATERAL (SELECT (ARRAY['application_status','job_alert','job_alert','recruiter_message','interview_scheduled'])[1 + v % 5] AS code) e
  CROSS JOIN LATERAL (SELECT now() - make_interval(mins => (seed.h(v, 512) * 480000)::int) AS at) t;

INSERT INTO notif.notification_delivery (notification_id, notification_channel_code, delivery_status_code, queued_at, sent_at, delivered_at,
                                         failure_reason, created_at, updated_at)
SELECT n.id, c.channel, s.status, n.created_at,
       CASE WHEN s.status IN ('sent', 'delivered', 'opened') THEN n.created_at + interval '5 seconds' END,
       CASE WHEN s.status IN ('delivered', 'opened') THEN n.created_at + interval '9 seconds' END,
       CASE WHEN s.status = 'failed' THEN 'Provider rejected the recipient' END, n.created_at, n.created_at
  FROM notif.notification n
  CROSS JOIN LATERAL (SELECT unnest(CASE WHEN n.id % 2 = 0 THEN ARRAY['email', 'push'] ELSE ARRAY['email'] END) AS channel) c
  CROSS JOIN LATERAL (SELECT (ARRAY['delivered','delivered','delivered','opened','sent','failed','suppressed','queued'])[1 + (n.id + length(c.channel)) % 8] AS status) s;

INSERT INTO notif.delivery_provider_receipt (notification_channel_code, provider_message_reference, notification_delivery_id, delivery_queued_at,
                                             received_at, created_at, updated_at)
SELECT d.notification_channel_code, 'prov-' || d.id, d.id, d.queued_at, d.sent_at, d.sent_at, d.sent_at
  FROM notif.notification_delivery d WHERE d.delivery_status_code IN ('sent', 'delivered', 'opened');

-- community, FAQs (question and answer are UI labels), support
INSERT INTO notif.community_post (author_app_user_id, post_body, post_body_language_id, posted_at, created_at, updated_at)
SELECT p.u_cand + 1 + floor(seed.h(v, 520) * p.n_cand)::bigint,
       (ARRAY['How do I prepare for a CNC operator interview?','Tips for a first job after college','Is a diploma enough for a supervisor role?',
              'Sharing my interview experience at a logistics firm'])[1 + v % 4], r.lang_en,
       now() - make_interval(days => (seed.h(v, 521) * 300)::int), now(), now()
  FROM seed.params p CROSS JOIN seed.refs r, generate_series(1, (SELECT greatest(10, n_cand / 20) FROM seed.params)) v;
INSERT INTO notif.community_reaction (community_post_id, app_user_id, reaction_type_code, created_at, updated_at)
SELECT cp.id, p.u_cand + 1 + ((cp.id * 7 + k * 13) % p.n_cand), (ARRAY['like','celebrate','insightful'])[1 + k % 3], now(), now()
  FROM notif.community_post cp CROSS JOIN seed.params p CROSS JOIN generate_series(1, 3) k
ON CONFLICT DO NOTHING;

INSERT INTO notif.faq (question_label_key, answer_label_key, ticket_category_code, is_published, sort_order)
SELECT ref.label_for('faq.question', q.question), ref.label_for('faq.answer', q.question || ' answer'), q.category, true, q.ord
  FROM (VALUES ('How do I reset my password?', 'account', 1), ('How do I update my resume?', 'account', 2),
               ('How do I recharge my wallet?', 'billing', 3), ('Where can I download my invoice?', 'billing', 4),
               ('How do I post a job?', 'job_post', 5), ('How do I close a job?', 'job_post', 6)) q(question, category, ord);

INSERT INTO notif.support_ticket (requester_app_user_id, assignee_app_user_id, ticket_category_code, ticket_status_code, ticket_subject,
                                  opened_at, resolved_at, created_at, updated_at)
SELECT p.u_cand + 1 + floor(seed.h(v, 530) * p.n_cand)::bigint, CASE WHEN v % 3 <> 0 THEN 2 + v % 5 END,
       (ARRAY['account','billing','job_post','other'])[1 + v % 4], st.status,
       (ARRAY['Cannot log in','Invoice missing','Job not visible','Question about plans'])[1 + v % 4],
       t.at, CASE WHEN st.status IN ('resolved', 'closed') THEN t.at + interval '2 days' END, t.at, t.at
  FROM seed.params p, generate_series(1, (SELECT greatest(10, n_cand / 50) FROM seed.params)) v
  CROSS JOIN LATERAL (SELECT now() - make_interval(days => 3 + (seed.h(v, 531) * 300)::int) AS at) t
  CROSS JOIN LATERAL (SELECT (ARRAY['open','in_progress','resolved','resolved','closed'])[1 + v % 5] AS status) st;
INSERT INTO notif.support_ticket_message (support_ticket_id, author_app_user_id, message_body, message_body_language_id, posted_at, created_at, updated_at)
SELECT t.id, CASE WHEN k = 1 THEN t.requester_app_user_id ELSE coalesce(t.assignee_app_user_id, 2) END,
       CASE WHEN k = 1 THEN 'I need help with this issue.' ELSE 'We are looking into it and will update you shortly.' END,
       (SELECT lang_en FROM seed.refs), t.opened_at + make_interval(hours => k), t.opened_at, t.opened_at
  FROM notif.support_ticket t CROSS JOIN generate_series(1, 2) k;

-- audit trail and error log
INSERT INTO audit.audit_event (actor_app_user_id, audit_action_code, subject_table, subject_id, event_detail, client_ip_masked, occurred_at, created_at)
SELECT CASE WHEN a.code = 'login_failed' AND v % 3 = 0 THEN NULL
            WHEN v % 2 = 0 THEN p.u_rec + 1 + (v % p.n_rec) ELSE p.u_cand + 1 + (v % p.n_cand) END,
       a.code, a.subject, 1 + (v % 1000), jsonb_build_object('seed', true), '203.0.113.x',
       now() - make_interval(mins => (seed.h(v, 540) * 525600)::int), now()
  FROM seed.params p, generate_series(1, (SELECT greatest(100, n_cand / 2) FROM seed.params)) v
  CROSS JOIN LATERAL (SELECT c.code, c.subject FROM (VALUES ('login_succeeded','admin.app_user'), ('login_failed','admin.app_user'),
                         ('profile_viewed','profile.candidate_profile'), ('profile_downloaded','profile.candidate_profile'),
                         ('role_granted','admin.user_role'), ('consent_changed','admin.consent_record'),
                         ('block_added','admin.block_list'), ('identifier_viewed','org.organisation_identifier')) c(code, subject)
                       OFFSET (v % 8) LIMIT 1) a;
INSERT INTO audit.error_log (error_severity_code, error_code, error_message, app_user_id, occurred_at, created_at)
SELECT (ARRAY['warning','warning','error','critical'])[1 + v % 4], (ARRAY['23505','40001','57014','PGW-502'])[1 + v % 4],
       (ARRAY['duplicate key value','serialization failure','statement timeout','payment gateway timeout'])[1 + v % 4],
       CASE WHEN v % 3 = 0 THEN p.u_rec + 1 + (v % p.n_rec) END, now() - make_interval(mins => (seed.h(v, 541) * 525600)::int), now()
  FROM seed.params p, generate_series(1, (SELECT greatest(10, n_cand / 50) FROM seed.params)) v;

SELECT count(*) AS deliveries FROM notif.notification_delivery \gset
SELECT count(*) AS audit_events FROM audit.audit_event \gset
\echo notification deliveries=:deliveries audit events=:audit_events
