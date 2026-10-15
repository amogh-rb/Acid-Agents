-- Shared access layer (Phase 4, owner A: B50, B53, B56, B59). Docket Section 3: every privilege is enforced in the
-- database, not only in the interface. The application connects as a login role that is a member of talentra_app
-- and runs every transaction with SET LOCAL app.current_user_id = <app_user.id>; Row-Level Security policies below
-- read that actor. Table owners and superusers bypass RLS (migrations, the test harness); the application never
-- connects as either.
--   * a recruiter sees and acts only on job requirements of the organisations they currently belong to
--     (org.recruiter_mapping in force today, or an organisation-scoped role grant)
--   * a consultant sees only published jobs open to consultants (and acts on them through src.sourcing_request)
--   * candidates and guests see published jobs only
--   * a candidate profile is hidden from any user or organisation the candidate blocked, and respects the
--     candidate's visibility setting; candidates never see other candidates
--   * recruiters cannot register candidates: only the user themself (or a platform admin) inserts a profile
--   * review finding F3: an interviewer must belong to the job's organisation

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
-- Actor helpers. SECURITY DEFINER so policies can read role and block data the caller cannot read directly.
CREATE FUNCTION app.actor_organisation_ids() RETURNS bigint[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
  SELECT coalesce(array_agg(DISTINCT org_id), '{}')
    FROM (SELECT organisation_id AS org_id FROM org.recruiter_mapping
           WHERE app_user_id = public.current_actor_id() AND valid_period @> current_date
          UNION
          SELECT organisation_id FROM admin.user_role
           WHERE app_user_id = public.current_actor_id() AND organisation_id IS NOT NULL AND valid_period @> now()) o
$$;

CREATE FUNCTION app.actor_has_role(p_role text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
  SELECT EXISTS (SELECT 1 FROM admin.user_role
                  WHERE app_user_id = public.current_actor_id() AND app_role_code = p_role AND valid_period @> now())
$$;

CREATE FUNCTION app.actor_is_platform_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
  SELECT EXISTS (SELECT 1 FROM admin.user_role
                  WHERE app_user_id = public.current_actor_id() AND app_role_code IN ('admin', 'super_admin')
                    AND valid_period @> now())
$$;

-- recruiter-side actors (employer, recruiter, consultant, placement officer)
CREATE FUNCTION app.actor_is_hiring_side() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
  SELECT EXISTS (SELECT 1 FROM admin.user_role
                  WHERE app_user_id = public.current_actor_id()
                    AND app_role_code IN ('employer', 'recruiter', 'consultant', 'placement_officer', 'account_admin')
                    AND valid_period @> now())
      OR EXISTS (SELECT 1 FROM org.recruiter_mapping
                  WHERE app_user_id = public.current_actor_id() AND valid_period @> current_date)
$$;

-- Can the current (hiring-side) actor see this candidate? Blocks and the visibility preference decide.
CREATE FUNCTION app.candidate_visible_to_actor(p_candidate_profile_id bigint, p_candidate_app_user_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
  SELECT NOT EXISTS (SELECT 1 FROM admin.block_list b
                      WHERE b.blocker_app_user_id = p_candidate_app_user_id AND b.deleted_at IS NULL
                        AND (b.blocked_app_user_id = public.current_actor_id()
                             OR b.blocked_organisation_id = ANY (app.actor_organisation_ids())))
     AND CASE coalesce((SELECT profile_visibility_code FROM notif.user_preference WHERE app_user_id = p_candidate_app_user_id),
                       'all_employers')
           WHEN 'all_employers' THEN true
           WHEN 'hidden'        THEN false
           ELSE EXISTS (SELECT 1 FROM job.application a JOIN job.job_requirement j ON j.id = a.job_requirement_id
                         WHERE a.candidate_profile_id = p_candidate_profile_id
                           AND j.organisation_id = ANY (app.actor_organisation_ids()))
         END
$$;

CREATE FUNCTION app.user_belongs_to_organisation(p_app_user_id bigint, p_organisation_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
  SELECT EXISTS (SELECT 1 FROM org.recruiter_mapping
                  WHERE app_user_id = p_app_user_id AND organisation_id = p_organisation_id AND valid_period @> current_date)
      OR EXISTS (SELECT 1 FROM admin.user_role
                  WHERE app_user_id = p_app_user_id AND organisation_id = p_organisation_id AND valid_period @> now())
$$;

REVOKE ALL ON FUNCTION app.actor_organisation_ids(), app.actor_has_role(text), app.actor_is_platform_admin(),
                       app.actor_is_hiring_side(), app.candidate_visible_to_actor(bigint, bigint),
                       app.user_belongs_to_organisation(bigint, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.actor_organisation_ids(), app.actor_has_role(text), app.actor_is_platform_admin(),
                          app.actor_is_hiring_side(), app.candidate_visible_to_actor(bigint, bigint),
                          app.user_belongs_to_organisation(bigint, bigint) TO talentra_app, talentra_readonly;

-- ---------------------------------------------------------------------------------------------------
-- job.job_requirement
ALTER TABLE job.job_requirement ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_job_requirement_select ON job.job_requirement FOR SELECT TO talentra_app USING (
     app.actor_is_platform_admin()
  OR organisation_id = ANY (app.actor_organisation_ids())
  OR (app.actor_has_role('consultant') AND is_open_to_consultant
      AND publish_state_code = 'published' AND deleted_at IS NULL)
  OR (NOT app.actor_is_hiring_side() AND publish_state_code = 'published' AND deleted_at IS NULL));
CREATE POLICY pol_job_requirement_insert ON job.job_requirement FOR INSERT TO talentra_app
  WITH CHECK (app.actor_is_platform_admin() OR organisation_id = ANY (app.actor_organisation_ids()));
CREATE POLICY pol_job_requirement_update ON job.job_requirement FOR UPDATE TO talentra_app
  USING (app.actor_is_platform_admin() OR organisation_id = ANY (app.actor_organisation_ids()))
  WITH CHECK (app.actor_is_platform_admin() OR organisation_id = ANY (app.actor_organisation_ids()));
CREATE POLICY pol_job_requirement_delete ON job.job_requirement FOR DELETE TO talentra_app
  USING (app.actor_is_platform_admin() OR organisation_id = ANY (app.actor_organisation_ids()));
CREATE POLICY pol_job_requirement_readonly ON job.job_requirement FOR SELECT TO talentra_readonly USING (true);

-- profile.candidate_profile
ALTER TABLE profile.candidate_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_candidate_profile_select ON profile.candidate_profile FOR SELECT TO talentra_app USING (
     app_user_id = public.current_actor_id()
  OR app.actor_is_platform_admin()
  OR (app.actor_is_hiring_side() AND deleted_at IS NULL AND app.candidate_visible_to_actor(id, app_user_id)));
CREATE POLICY pol_candidate_profile_insert ON profile.candidate_profile FOR INSERT TO talentra_app
  WITH CHECK (app_user_id = public.current_actor_id() OR app.actor_is_platform_admin());
CREATE POLICY pol_candidate_profile_update ON profile.candidate_profile FOR UPDATE TO talentra_app
  USING (app_user_id = public.current_actor_id() OR app.actor_is_platform_admin())
  WITH CHECK (app_user_id = public.current_actor_id() OR app.actor_is_platform_admin());
CREATE POLICY pol_candidate_profile_delete ON profile.candidate_profile FOR DELETE TO talentra_app
  USING (app.actor_is_platform_admin());
CREATE POLICY pol_candidate_profile_readonly ON profile.candidate_profile FOR SELECT TO talentra_readonly USING (true);

-- profile.candidate_contact: visible exactly when the profile is (the subquery is itself filtered by RLS)
ALTER TABLE profile.candidate_contact ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_candidate_contact_select ON profile.candidate_contact FOR SELECT TO talentra_app
  USING (EXISTS (SELECT 1 FROM profile.candidate_profile cp WHERE cp.id = candidate_profile_id));
CREATE POLICY pol_candidate_contact_write ON profile.candidate_contact FOR ALL TO talentra_app
  USING (EXISTS (SELECT 1 FROM profile.candidate_profile cp WHERE cp.id = candidate_profile_id AND cp.app_user_id = public.current_actor_id()))
  WITH CHECK (EXISTS (SELECT 1 FROM profile.candidate_profile cp WHERE cp.id = candidate_profile_id AND cp.app_user_id = public.current_actor_id()));
CREATE POLICY pol_candidate_contact_readonly ON profile.candidate_contact FOR SELECT TO talentra_readonly USING (true);

-- job.application: the candidate sees their own; the hiring organisation sees applications to its jobs
ALTER TABLE job.application ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_application_select ON job.application FOR SELECT TO talentra_app USING (
     app.actor_is_platform_admin()
  OR EXISTS (SELECT 1 FROM profile.candidate_profile cp WHERE cp.id = candidate_profile_id AND cp.app_user_id = public.current_actor_id())
  OR EXISTS (SELECT 1 FROM job.job_requirement j WHERE j.id = job_requirement_id AND j.organisation_id = ANY (app.actor_organisation_ids())));
CREATE POLICY pol_application_insert ON job.application FOR INSERT TO talentra_app WITH CHECK (
     EXISTS (SELECT 1 FROM profile.candidate_profile cp WHERE cp.id = candidate_profile_id AND cp.app_user_id = public.current_actor_id())
  OR EXISTS (SELECT 1 FROM job.job_requirement j WHERE j.id = job_requirement_id AND j.organisation_id = ANY (app.actor_organisation_ids())));
CREATE POLICY pol_application_update ON job.application FOR UPDATE TO talentra_app
  USING (app.actor_is_platform_admin()
         OR EXISTS (SELECT 1 FROM profile.candidate_profile cp WHERE cp.id = candidate_profile_id AND cp.app_user_id = public.current_actor_id())
         OR EXISTS (SELECT 1 FROM job.job_requirement j WHERE j.id = job_requirement_id AND j.organisation_id = ANY (app.actor_organisation_ids())));
CREATE POLICY pol_application_readonly ON job.application FOR SELECT TO talentra_readonly USING (true);

-- ---------------------------------------------------------------------------------------------------
-- F3: the interviewer must belong to the organisation that owns the job
CREATE FUNCTION job.check_interviewer_organisation() RETURNS trigger
LANGUAGE plpgsql AS
$$
DECLARE
  v_org bigint;
BEGIN
  IF NEW.interviewer_app_user_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT j.organisation_id INTO v_org
    FROM job.application a JOIN job.job_requirement j ON j.id = a.job_requirement_id
   WHERE a.id = NEW.application_id AND a.candidate_profile_id = NEW.candidate_profile_id;
  IF NOT app.user_belongs_to_organisation(NEW.interviewer_app_user_id, v_org) THEN
    RAISE EXCEPTION 'trg_interview_interviewer_organisation: user % does not belong to organisation %',
                    NEW.interviewer_app_user_id, v_org USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_interview_interviewer_organisation BEFORE INSERT OR UPDATE OF interviewer_app_user_id ON job.interview
  FOR EACH ROW EXECUTE FUNCTION job.check_interviewer_organisation();
