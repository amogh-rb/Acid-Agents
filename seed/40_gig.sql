-- M19 seed, step 4 (Gig marketplace): workers, offerings, rates, availability, requests, applications, assignments
-- (with deliberate overlap attempts), handoffs, earnings, ratings, lists.
\ir _preamble.sql

INSERT INTO gig.gig_worker_profile (id, app_user_id, headline, bio, bio_language_id, base_city_id, is_available, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT k, p.u_gw + k,
       (ARRAY['Event host and coordinator','Warehouse and loading helper','Delivery partner','Data entry operator','Field survey agent','Retail promoter'])[1 + k % 6],
       CASE WHEN seed.h(k, 300) < 0.5 THEN 'Reliable and punctual, available on weekends.' END,
       CASE WHEN seed.h(k, 300) < 0.5 THEN r.lang_en END,
       CASE WHEN seed.h(k, 301) < 0.9 THEN r.cities[1 + floor(power(seed.h(k, 302), 1.7) * array_length(r.cities, 1))::int] END,
       seed.h(k, 303) < 0.8,
       now() - make_interval(days => 30 + (seed.h(k, 304) * 600)::int), now()
  FROM seed.params p CROSS JOIN seed.refs r, generate_series(1, (SELECT n_gw FROM seed.params)) k;

INSERT INTO gig.gig_service_offering (gig_worker_profile_id, skill_id, offering_title, offering_description, created_at, updated_at)
SELECT w.id, r.skills[1 + (w.id + j * 3) % array_length(r.skills, 1)], 'Service ' || j || ' of worker ' || w.id,
       CASE WHEN j = 1 THEN 'Experienced and available on short notice' END, w.created_at, w.created_at
  FROM gig.gig_worker_profile w CROSS JOIN seed.refs r CROSS JOIN generate_series(1, 2) j;
INSERT INTO gig.gig_charge_rate (gig_service_offering_id, rate_unit_code, rate_amount, rate_currency_code, valid_period, created_at, updated_at)
SELECT o.id, 'hour', round(200 + seed.h(o.id, 310) * 1300, -1), 'INR', daterange(date '2025-01-01', NULL), o.created_at, o.created_at
  FROM gig.gig_service_offering o;
INSERT INTO gig.gig_availability (gig_worker_profile_id, available_from, available_to, created_at, updated_at)
SELECT w.id, date_trunc('day', now()) + make_interval(days => j * 7) + interval '9 hours',
       date_trunc('day', now()) + make_interval(days => j * 7) + interval '17 hours', w.created_at, w.created_at
  FROM gig.gig_worker_profile w CROSS JOIN generate_series(1, 3) j;

-- ---------------------------------------------------------------------------------------------------
-- Requests: half posted by recruiters of an organisation, half by individual requesters
CREATE UNLOGGED TABLE seed.gig_plan AS
SELECT g AS id,
       CASE WHEN g % 2 = 0 THEN p.u_rec + 1 + (g % p.n_rec) ELSE p.u_requester + 1 + (g % p.n_requester) END AS requester,
       CASE WHEN g % 2 = 0 THEN 1 + (g % p.n_rec) % p.n_hiring END AS requester_org,
       now() - interval '200 days' + (seed.h(g, 320) * 400) * interval '1 day' AS wstart,
       (4 + floor(seed.h(g, 321) * 9)) * interval '1 hour' AS wlen,
       seed.h(g, 322) AS r_status, seed.h(g, 323) AS r_price
  FROM seed.params p, generate_series(1, (SELECT n_gig FROM seed.params)) g;

INSERT INTO gig.gig_request (id, requester_app_user_id, requester_organisation_id, gig_title, gig_description, gig_description_language_id,
       skill_id, city_id, window_start, window_end, pricing_model_code, fixed_price_amount, rate_amount, rate_unit_code, currency_code,
       gig_request_status_code, created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT gp.id, gp.requester, gp.requester_org,
       (ARRAY['Product launch host','Expo booth staff','Warehouse loading help','Market survey','Event ushers','Door-to-door promotion'])[1 + gp.id % 6],
       'Short project: details shared after acceptance. Reference ' || gp.id || '.', r.lang_en,
       r.skills[1 + (gp.id % array_length(r.skills, 1))],
       CASE WHEN seed.h(gp.id, 324) < 0.8 THEN r.cities[1 + (gp.id % array_length(r.cities, 1))] END,
       gp.wstart, gp.wstart + gp.wlen,
       CASE WHEN gp.r_price < 0.6 THEN 'fixed' ELSE 'rate' END,
       CASE WHEN gp.r_price < 0.6 THEN round(2000 + seed.h(gp.id, 325) * 28000, -2) END,
       CASE WHEN gp.r_price >= 0.6 THEN round(200 + seed.h(gp.id, 326) * 1300, -1) END,
       CASE WHEN gp.r_price >= 0.6 THEN 'hour' END,
       'INR',
       CASE WHEN gp.wstart + gp.wlen < now()
            THEN (ARRAY['completed','completed','completed','completed','completed','completed','completed','cancelled','open','open'])[1 + (gp.id % 10)]
            ELSE (ARRAY['open','open','open','open','open','open','open','assigned','assigned','draft'])[1 + (gp.id % 10)] END,
       least(now() - interval '1 day', gp.wstart - interval '15 days'), least(now() - interval '1 day', gp.wstart - interval '14 days')
  FROM seed.gig_plan gp CROSS JOIN seed.refs r;

-- applications (about 5 per non-draft request): the first applicant wins completed/assigned requests
INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id, gig_application_status_code, proposed_amount, proposed_currency_code,
                                 applied_at, decided_at, created_at, updated_at)
SELECT r.id, 1 + ((r.id * 7 + k * 997) % p.n_gw), s.status,
       CASE WHEN seed.h(r.id * 6 + k, 330) < 0.30 THEN round(1500 + seed.h(r.id * 6 + k, 331) * 20000, -2) END,
       CASE WHEN seed.h(r.id * 6 + k, 330) < 0.30 THEN 'INR' END,
       r.created_at + interval '1 day' + k * interval '2 hours',
       CASE WHEN s.status IN ('accepted', 'rejected') THEN r.created_at + interval '2 days' END,
       r.created_at, r.created_at
  FROM gig.gig_request r CROSS JOIN seed.params p CROSS JOIN generate_series(1, 5) k
  CROSS JOIN LATERAL (SELECT CASE WHEN r.gig_request_status_code IN ('completed', 'assigned') AND k = 1 THEN 'accepted'
                                  WHEN r.gig_request_status_code IN ('completed', 'assigned') THEN (ARRAY['rejected','rejected','withdrawn'])[1 + k % 3]
                                  WHEN r.gig_request_status_code = 'cancelled' THEN 'withdrawn'
                                  ELSE 'applied' END AS status) s
 WHERE r.gig_request_status_code <> 'draft';

-- assignments: overlapping windows for one worker are rejected by ex_gig_assignment_worker_window (DO NOTHING skips them)
CREATE TEMP TABLE tmp_attempt AS
SELECT a.id AS gig_application_id, a.gig_request_id, a.gig_worker_profile_id, r.window_start, r.window_end,
       CASE r.gig_request_status_code WHEN 'completed' THEN 'completed'
            ELSE (ARRAY['active','handed_off'])[1 + a.id % 2] END AS status
  FROM gig.gig_application a JOIN gig.gig_request r ON r.id = a.gig_request_id
 WHERE a.gig_application_status_code = 'accepted';
SELECT count(*) AS assignment_attempts FROM tmp_attempt \gset

INSERT INTO gig.gig_assignment (gig_application_id, gig_request_id, gig_worker_profile_id, window_start, window_end,
                                gig_assignment_status_code, completed_at, created_at, updated_at)
SELECT gig_application_id, gig_request_id, gig_worker_profile_id, window_start, window_end, status,
       CASE WHEN status = 'completed' THEN window_end END, window_start - interval '1 day', window_start - interval '1 day'
  FROM tmp_attempt ORDER BY gig_worker_profile_id, window_start
ON CONFLICT DO NOTHING;
SELECT count(*) AS assignments FROM gig.gig_assignment \gset

-- accepted applications that lost to an overlap are rejected, and their request is cancelled
UPDATE gig.gig_application a SET gig_application_status_code = 'rejected'
 WHERE a.gig_application_status_code = 'accepted'
   AND NOT EXISTS (SELECT 1 FROM gig.gig_assignment s WHERE s.gig_application_id = a.id);
UPDATE gig.gig_request r SET gig_request_status_code = 'cancelled'
 WHERE r.gig_request_status_code IN ('completed', 'assigned')
   AND NOT EXISTS (SELECT 1 FROM gig.gig_assignment s WHERE s.gig_request_id = r.id);

SELECT seed.sync_sequences() AS sequences_synced \gset

-- explicit overlap attempts: a second, accepted application for the same worker and the same window must be refused
CREATE TABLE seed.gig_overlap_attempt (attempted integer, rejected integer);
DO $$
DECLARE
  r record;
  v_req bigint;
  v_app bigint;
  v_attempted integer := 0;
  v_rejected integer := 0;
BEGIN
  FOR r IN SELECT s.gig_worker_profile_id, s.window_start, s.window_end, q.requester_app_user_id, q.skill_id
             FROM gig.gig_assignment s JOIN gig.gig_request q ON q.id = s.gig_request_id
            WHERE s.gig_assignment_status_code IN ('active', 'handed_off') ORDER BY s.id LIMIT 300 LOOP
    v_attempted := v_attempted + 1;
    BEGIN
      INSERT INTO gig.gig_request (requester_app_user_id, gig_title, gig_description, skill_id, window_start, window_end, pricing_model_code,
                                   fixed_price_amount, currency_code, gig_request_status_code)
      VALUES (r.requester_app_user_id, 'Overlap attempt', 'Conflicting booking', r.skill_id, r.window_start + interval '1 hour', r.window_end,
              'fixed', 1000, 'INR', 'assigned') RETURNING id INTO v_req;
      INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id, gig_application_status_code, decided_at)
      VALUES (v_req, r.gig_worker_profile_id, 'accepted', now()) RETURNING id INTO v_app;
      INSERT INTO gig.gig_assignment (gig_application_id, gig_request_id, gig_worker_profile_id, window_start, window_end)
      VALUES (v_app, v_req, r.gig_worker_profile_id, r.window_start + interval '1 hour', r.window_end);
    EXCEPTION WHEN exclusion_violation THEN
      v_rejected := v_rejected + 1;     -- the whole block (request and application too) is rolled back
    END;
  END LOOP;
  INSERT INTO seed.gig_overlap_attempt VALUES (v_attempted, v_rejected);
END $$;
SELECT attempted AS overlap_attempted, rejected AS overlap_rejected FROM seed.gig_overlap_attempt \gset
\echo gig assignment attempts=:assignment_attempts inserted=:assignments; explicit overlap attempts=:overlap_attempted rejected by exclusion constraint=:overlap_rejected

-- handoff to the fulfilment system, earnings from it, ratings by requesters, favourites and blacklists
INSERT INTO gig.gig_fulfilment_handoff (gig_assignment_id, idempotency_key, external_reference, handoff_status_code, sent_at, acknowledged_at,
                                        created_at, updated_at)
SELECT s.id, 'seed-handoff-' || s.id, 'FUL-' || s.id, 'acknowledged', s.created_at + interval '1 hour', s.created_at + interval '2 hours',
       s.created_at, s.created_at
  FROM gig.gig_assignment s WHERE s.gig_assignment_status_code IN ('handed_off', 'completed');

INSERT INTO gig.gig_earning_reference (gig_assignment_id, earning_kind_code, earning_amount, currency_code, source_system, source_reference,
                                       as_of, reconciled_at, created_at)
SELECT s.id, CASE WHEN s.gig_assignment_status_code = 'completed' THEN 'total' ELSE 'estimated' END,
       coalesce(q.fixed_price_amount, q.rate_amount * extract(epoch FROM (s.window_end - s.window_start)) / 3600), 'INR',
       'fulfil-x', 'seed-evt-' || s.id, coalesce(s.completed_at, s.created_at + interval '3 hours'), now(), now()
  FROM gig.gig_assignment s JOIN gig.gig_request q ON q.id = s.gig_request_id
 WHERE s.gig_assignment_status_code IN ('handed_off', 'completed');

INSERT INTO gig.gig_rating (gig_assignment_id, rating_score, review_text, review_language_id, created_at, updated_at, created_by, updated_by)
SELECT s.id, 3 + (s.id % 3), CASE WHEN s.id % 3 = 0 THEN 'Good work, on time.' END,
       CASE WHEN s.id % 3 = 0 THEN (SELECT lang_en FROM seed.refs) END, s.completed_at + interval '1 day', s.completed_at + interval '1 day',
       q.requester_app_user_id, q.requester_app_user_id
  FROM gig.gig_assignment s JOIN gig.gig_request q ON q.id = s.gig_request_id
 WHERE s.gig_assignment_status_code = 'completed' AND seed.h(s.id, 340) < 0.85;

INSERT INTO gig.gig_requester_worker_list (requester_app_user_id, gig_worker_profile_id, worker_list_kind_code, list_note, created_at, updated_at)
SELECT p.u_requester + 1 + (v % p.n_requester), 1 + ((v * 31) % p.n_gw), CASE WHEN v % 4 = 0 THEN 'blacklist' ELSE 'favourite' END,
       CASE WHEN v % 4 = 0 THEN 'No show' END, now() - make_interval(days => (v % 200)::int), now()
  FROM seed.params p, generate_series(1, (SELECT n_gig / 2 FROM seed.params)) v
ON CONFLICT DO NOTHING;

SELECT count(*) AS gig_requests FROM gig.gig_request \gset
SELECT count(*) AS gig_applications FROM gig.gig_application \gset
\echo gig_requests=:gig_requests gig_applications=:gig_applications assignments=:assignments
