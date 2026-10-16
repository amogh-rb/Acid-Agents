-- Privacy and retention (Phase 5, M22, owner A: B75-B79). Delivery Plan 3.5:
--   * deletion on request anonymises Personal columns and sets deleted_at; a scheduled job purges after the stated
--     window; inactivity rule per entity (candidate profile: 36 months)
--   * RLS extends from the profile and its contacts (M18) to every other Personal table of the profile
-- Retention windows are the ones stated in the table comments:
--   candidate_profile 30 days after a deletion request / 36 months inactive; login_session 90 days after end;
--   login_attempt 1 year; session_revocation 1 year; notification 180 days (deliveries go with it, and old delivery
--   months are dropped as partitions); support_ticket 2 years after resolution; error_log 90 days; audit_event 7 years.

SET app.current_user_id = '1';

SELECT ref.add_lookup_value('ref.audit_action', 'user_anonymised',  'User anonymised',  19);
SELECT ref.add_lookup_value('ref.audit_action', 'retention_purged', 'Retention purge',  20);

ALTER TABLE admin.app_user ADD COLUMN anonymised_at timestamptz;
COMMENT ON COLUMN admin.app_user.anonymised_at IS '[Internal] When the identity and its candidate profile were anonymised (deletion request or inactivity); null: not anonymised';
CREATE INDEX idx_app_user_last_login_at ON admin.app_user (last_login_at) WHERE anonymised_at IS NULL AND NOT is_system_actor;

-- ---------------------------------------------------------------------------------------------------
-- RLS on the remaining Personal tables of the profile. Same rule as candidate_contact: a row is visible exactly when
-- its profile is (the EXISTS subquery is itself filtered by the candidate_profile policy); only the candidate (or a
-- platform admin) writes. Identity documents are stricter: never visible to the hiring side.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['candidate_address', 'candidate_education', 'candidate_work_experience', 'candidate_skill',
                           'candidate_language', 'candidate_certification', 'candidate_project', 'candidate_preferred_location',
                           'candidate_preferred_role', 'candidate_web_link', 'resume_version', 'course_enrolment',
                           'profile_completion_score', 'assessment_attempt'] LOOP
    EXECUTE format('ALTER TABLE profile.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format($p$CREATE POLICY %I ON profile.%I FOR SELECT TO talentra_app
                      USING (app.candidate_profile_visible(candidate_profile_id, (SELECT app.actor_is_platform_admin()),
                             (SELECT app.actor_is_hiring_side()), (SELECT app.actor_organisation_ids()),
                             (SELECT app.actor_blocking_user_ids())))$p$,
                   'pol_' || t || '_select', t);
    EXECUTE format($p$CREATE POLICY %I ON profile.%I FOR ALL TO talentra_app
                      USING ((SELECT app.actor_is_platform_admin()) OR app.actor_owns_candidate_profile(candidate_profile_id))
                      WITH CHECK ((SELECT app.actor_is_platform_admin()) OR app.actor_owns_candidate_profile(candidate_profile_id))$p$,
                   'pol_' || t || '_write', t);
    EXECUTE format('CREATE POLICY %I ON profile.%I FOR SELECT TO talentra_readonly USING (true)', 'pol_' || t || '_readonly', t);
  END LOOP;
END $$;

ALTER TABLE profile.candidate_identity_document ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_candidate_identity_document_owner ON profile.candidate_identity_document FOR ALL TO talentra_app
  USING ((SELECT app.actor_is_platform_admin()) OR app.actor_owns_candidate_profile(candidate_profile_id))
  WITH CHECK ((SELECT app.actor_is_platform_admin()) OR app.actor_owns_candidate_profile(candidate_profile_id));
CREATE POLICY pol_candidate_identity_document_readonly ON profile.candidate_identity_document FOR SELECT TO talentra_readonly USING (true);

-- ---------------------------------------------------------------------------------------------------
-- Free-text candidate search for the hiring side (M22, D36). Under RLS, ILIKE is not leakproof, so PostgreSQL may not
-- evaluate it before the policy and cannot use the trigram index: a recruiter's name search scanned every visible
-- profile (measured: 3.3 s for a top 50, minutes for a count). This function runs as owner, uses the trigram index,
-- and applies exactly the candidate_profile SELECT policy to the matches only. The application calls it instead of
-- querying candidate_profile with ILIKE.
CREATE FUNCTION app.search_candidates_by_name(p_text text, p_limit integer DEFAULT 50)
RETURNS TABLE (candidate_profile_id bigint, full_name varchar, current_city_id bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_admin  boolean := app.actor_is_platform_admin();
  v_hiring boolean := app.actor_is_hiring_side();
  v_orgs   bigint[] := app.actor_organisation_ids();
  v_blk    bigint[] := app.actor_blocking_user_ids();
  v_like   text;
BEGIN
  IF length(btrim(coalesce(p_text, ''))) < 3 THEN
    RAISE EXCEPTION 'search_candidates_by_name: at least 3 characters are required' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF NOT (v_admin OR v_hiring) THEN
    RETURN;                                    -- candidates and guests never search other candidates
  END IF;
  v_like := '%' || replace(replace(replace(btrim(p_text), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  RETURN QUERY
    SELECT cp.id, cp.full_name::varchar, cp.current_city_id
      FROM profile.candidate_profile cp
     WHERE cp.full_name ILIKE v_like
       AND (v_admin OR (cp.deleted_at IS NULL AND app.candidate_visible_to_actor(cp.id, cp.app_user_id, v_orgs, v_blk)))
     ORDER BY cp.id
     LIMIT least(greatest(p_limit, 1), 200);
END
$$;
REVOKE ALL ON FUNCTION app.search_candidates_by_name(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.search_candidates_by_name(text, integer) TO talentra_app;
COMMENT ON FUNCTION app.search_candidates_by_name(text, integer) IS
  'Hiring-side candidate name search (>= 3 characters, at most 200 rows): trigram index first, then the candidate_profile visibility rule (blocks, visibility preference, deleted) on the matches only';

-- ---------------------------------------------------------------------------------------------------
-- Anonymisation. Keeps the rows that history depends on (profile, applications, status history, resume versions
-- referenced by applications, ledgers, audit) and removes or blanks every Personal value. Idempotent.
CREATE FUNCTION admin.anonymise_user(p_app_user_id bigint, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_user    admin.app_user%ROWTYPE;
  v_profile bigint;
  v_n       jsonb := '{}';
  v_count   bigint;
  t         text;
BEGIN
  SELECT * INTO v_user FROM admin.app_user WHERE id = p_app_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'anonymise_user: user % does not exist', p_app_user_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_user.is_system_actor THEN
    RAISE EXCEPTION 'anonymise_user: the system actor cannot be anonymised' USING ERRCODE = 'check_violation';
  END IF;
  -- the user themself, a platform admin, or the retention job (system actor) may anonymise
  IF public.current_actor_id() IS DISTINCT FROM p_app_user_id AND NOT app.actor_is_platform_admin()
     AND NOT coalesce((SELECT is_system_actor FROM admin.app_user WHERE id = public.current_actor_id()), false) THEN
    RAISE EXCEPTION 'anonymise_user: actor % may not anonymise user %', public.current_actor_id(), p_app_user_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_user.anonymised_at IS NOT NULL THEN
    RETURN jsonb_build_object('app_user_id', p_app_user_id, 'already_anonymised_at', v_user.anonymised_at);
  END IF;

  SELECT id INTO v_profile FROM profile.candidate_profile WHERE app_user_id = p_app_user_id;
  IF v_profile IS NOT NULL THEN
    UPDATE profile.candidate_profile
       SET full_name = 'Anonymised user', given_name = NULL, family_name = NULL, date_of_birth = NULL, gender_code = NULL,
           nationality_country_id = NULL, current_city_id = NULL, headline = NULL, summary = NULL, summary_language_id = NULL,
           current_salary_disclosure_code = 'not_disclosed', current_salary_amount = NULL,
           expected_salary_disclosure_code = 'not_disclosed', expected_salary_amount = NULL,
           currency_code = NULL, pay_period_code = NULL, notice_period_code = NULL, is_open_to_work = false,
           deleted_at = coalesce(deleted_at, now())
     WHERE id = v_profile;
    -- owned Personal children are deleted (projects first: they reference work experience)
    FOREACH t IN ARRAY ARRAY['candidate_project', 'candidate_contact', 'candidate_address', 'candidate_identity_document',
                             'candidate_web_link', 'candidate_education', 'candidate_work_experience', 'candidate_certification',
                             'candidate_skill', 'candidate_language', 'candidate_preferred_location', 'candidate_preferred_role',
                             'course_enrolment', 'profile_completion_score'] LOOP
      EXECUTE format('DELETE FROM profile.%I WHERE candidate_profile_id = $1', t) USING v_profile;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      v_n := v_n || jsonb_build_object(t, v_count);
    END LOOP;
    -- resume versions stay (applications reference them) but lose their content
    UPDATE profile.resume_version
       SET body = '[anonymised]', body_language_id = NULL, file_storage_key = NULL, file_mime_type = NULL,
           file_size_bytes = NULL, version_label = NULL, is_default = false, deleted_at = coalesce(deleted_at, now())
     WHERE candidate_profile_id = v_profile;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_n := v_n || jsonb_build_object('resume_version_blanked', v_count);
    DELETE FROM job.saved_search WHERE candidate_profile_id = v_profile;
    -- applications stay (pipeline history and employer statistics) but lose the candidate's free text
    UPDATE job.application SET cover_note = NULL WHERE candidate_profile_id = v_profile AND cover_note IS NOT NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_n := v_n || jsonb_build_object('application_cover_note_cleared', v_count);
  END IF;

  -- the login identity: no identifier left, sessions ended, credential and devices removed
  UPDATE lic.login_session SET ended_at = now(), session_end_reason_code = 'revoked'
   WHERE app_user_id = p_app_user_id AND ended_at IS NULL;
  DELETE FROM admin.user_credential WHERE app_user_id = p_app_user_id;
  UPDATE admin.app_user
     SET login_email = NULL, login_phone = NULL, login_phone_country_id = NULL, display_name = NULL,
         user_status_code = 'deactivated', deleted_at = coalesce(deleted_at, now()), anonymised_at = now()
   WHERE id = p_app_user_id;

  PERFORM audit.log_event('user_anonymised', 'admin.app_user', p_app_user_id,
                          jsonb_build_object('reason', p_reason, 'candidate_profile_id', v_profile, 'rows', v_n));
  RETURN jsonb_build_object('app_user_id', p_app_user_id, 'candidate_profile_id', v_profile, 'rows', v_n);
END
$$;
REVOKE ALL ON FUNCTION admin.anonymise_user(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin.anonymise_user(bigint, text) TO talentra_app;
COMMENT ON FUNCTION admin.anonymise_user(bigint, text) IS
  'Anonymise a login identity and its candidate profile (deletion request, or inactivity via admin.run_retention). Allowed for the user themself, a platform admin or the system actor; audited; idempotent';

-- ---------------------------------------------------------------------------------------------------
-- Retention job. Run daily by the scheduler as the database owner (see tools/run_retention.ps1):
--   SET app.current_user_id = '1'; SELECT admin.run_retention();
-- p_as_of exists so the windows can be tested; production passes nothing.
CREATE FUNCTION admin.run_retention(p_as_of timestamptz DEFAULT now()) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_n     jsonb := '{}';
  v_count bigint;
  r       record;
BEGIN
  IF NOT coalesce((SELECT is_system_actor FROM admin.app_user WHERE id = public.current_actor_id()), false) THEN
    RAISE EXCEPTION 'run_retention: must run as the system actor (SET app.current_user_id = 1)' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM set_config('app.retention_purge', 'on', true);   -- this transaction only (see audit.forbid_update_delete)

  -- 1. candidates: 30 days after a deletion request, or 36 months without a login
  v_count := 0;
  FOR r IN SELECT u.id FROM admin.app_user u
            WHERE u.anonymised_at IS NULL AND NOT u.is_system_actor
              AND (EXISTS (SELECT 1 FROM profile.candidate_profile cp
                            WHERE cp.app_user_id = u.id AND cp.deleted_at <= p_as_of - interval '30 days')
                   OR (EXISTS (SELECT 1 FROM profile.candidate_profile cp WHERE cp.app_user_id = u.id)
                       AND coalesce(u.last_login_at, u.created_at) <= p_as_of - interval '36 months'))
            ORDER BY u.id LOOP
    PERFORM admin.anonymise_user(r.id, 'retention');
    v_count := v_count + 1;
  END LOOP;
  v_n := v_n || jsonb_build_object('users_anonymised', v_count);

  -- 2. sessions and login history
  DELETE FROM lic.session_revocation WHERE revoked_at <= p_as_of - interval '1 year';
  GET DIAGNOSTICS v_count = ROW_COUNT;  v_n := v_n || jsonb_build_object('session_revocation', v_count);
  DELETE FROM lic.login_session s WHERE s.ended_at <= p_as_of - interval '90 days'
     AND NOT EXISTS (SELECT 1 FROM lic.session_revocation v WHERE v.login_session_id = s.id);
  GET DIAGNOSTICS v_count = ROW_COUNT;  v_n := v_n || jsonb_build_object('login_session', v_count);
  DELETE FROM lic.login_attempt WHERE attempted_at <= p_as_of - interval '1 year';
  GET DIAGNOSTICS v_count = ROW_COUNT;  v_n := v_n || jsonb_build_object('login_attempt', v_count);

  -- 3. notifications (their deliveries and receipts cascade), then whole delivery months past the window
  DELETE FROM notif.notification WHERE created_at <= p_as_of - interval '180 days';
  GET DIAGNOSTICS v_count = ROW_COUNT;  v_n := v_n || jsonb_build_object('notification', v_count);
  v_count := 0;
  FOR r IN SELECT c.oid::regclass AS part
             FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
            WHERE i.inhparent = 'notif.notification_delivery'::regclass AND c.relname ~ '_p[0-9]{6}$'
              AND to_date(right(c.relname, 6), 'YYYYMM') + interval '1 month' <= p_as_of - interval '180 days' LOOP
    EXECUTE format('ALTER TABLE notif.notification_delivery DETACH PARTITION %s', r.part);
    EXECUTE format('DROP TABLE %s', r.part);
    v_count := v_count + 1;
  END LOOP;
  v_n := v_n || jsonb_build_object('delivery_partitions_dropped', v_count);

  -- 4. support tickets 2 years after resolution (messages cascade), error log 90 days, audit trail 7 years
  DELETE FROM notif.support_ticket WHERE resolved_at <= p_as_of - interval '2 years';
  GET DIAGNOSTICS v_count = ROW_COUNT;  v_n := v_n || jsonb_build_object('support_ticket', v_count);
  DELETE FROM audit.error_log WHERE occurred_at <= p_as_of - interval '90 days';
  GET DIAGNOSTICS v_count = ROW_COUNT;  v_n := v_n || jsonb_build_object('error_log', v_count);
  DELETE FROM audit.audit_event WHERE occurred_at <= p_as_of - interval '7 years';
  GET DIAGNOSTICS v_count = ROW_COUNT;  v_n := v_n || jsonb_build_object('audit_event', v_count);

  PERFORM set_config('app.retention_purge', 'off', true);
  PERFORM audit.log_event('retention_purged', 'admin.run_retention', NULL, v_n || jsonb_build_object('as_of', p_as_of));
  RETURN v_n;
END
$$;
REVOKE ALL ON FUNCTION admin.run_retention(timestamptz) FROM PUBLIC;
COMMENT ON FUNCTION admin.run_retention(timestamptz) IS
  'Daily retention job (D35): anonymises candidates past their window and deletes rows past the retention stated in each table comment; owner/system actor only; audited';
