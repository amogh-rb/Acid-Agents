-- Administration (schemas admin, audit). Owner A. Phase 2: M7-M10 (B24, B27, B30, B33).
-- Entities and relationships: docs/phase2/admin_entities.md, admin_relationships.md.
-- Extends the admin.app_user stub (ddl/15_stubs.sql) with ALTER TABLE; no Phase 1 FK changes.
-- Role-based access enforcement (RLS, login roles) is layered on in M18; this file holds the data it reads.

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
-- Lookups owned by this module
SELECT ref.create_lookup('ref.hash_algorithm', 'password hashing algorithm of a stored credential');
SELECT ref.add_lookup_value('ref.hash_algorithm', 'argon2id',      'Argon2id',                 1);
SELECT ref.add_lookup_value('ref.hash_algorithm', 'bcrypt_legacy', 'bcrypt (legacy, rehash at next login)', 2);

SELECT ref.create_lookup('ref.consent_purpose', 'purpose a user gives or withdraws consent for');
SELECT ref.add_lookup_value('ref.consent_purpose', 'terms_of_service',     'Terms of service',               1);
SELECT ref.add_lookup_value('ref.consent_purpose', 'privacy_policy',       'Privacy policy',                 2);
SELECT ref.add_lookup_value('ref.consent_purpose', 'profile_visibility',   'Profile visible to employers',   3);
SELECT ref.add_lookup_value('ref.consent_purpose', 'marketing_email',      'Marketing email',                4);
SELECT ref.add_lookup_value('ref.consent_purpose', 'marketing_sms',        'Marketing SMS',                  5);
SELECT ref.add_lookup_value('ref.consent_purpose', 'identity_verification', 'Identity verification',         6);

SELECT ref.create_lookup('ref.audit_action', 'sensitive action recorded in the audit trail');
SELECT ref.add_lookup_value('ref.audit_action', 'login_succeeded',       'Login succeeded',            1);
SELECT ref.add_lookup_value('ref.audit_action', 'login_failed',          'Login failed',               2);
SELECT ref.add_lookup_value('ref.audit_action', 'device_limit_exceeded', 'Device limit exceeded',      3);
SELECT ref.add_lookup_value('ref.audit_action', 'session_revoked',       'Session revoked',            4);
SELECT ref.add_lookup_value('ref.audit_action', 'device_revoked',        'Device revoked',             5);
SELECT ref.add_lookup_value('ref.audit_action', 'credential_changed',    'Credential changed',         6);
SELECT ref.add_lookup_value('ref.audit_action', 'role_granted',          'Role granted',               7);
SELECT ref.add_lookup_value('ref.audit_action', 'role_revoked',          'Role revoked',               8);
SELECT ref.add_lookup_value('ref.audit_action', 'block_added',           'Block added',                9);
SELECT ref.add_lookup_value('ref.audit_action', 'block_removed',         'Block removed',              10);
SELECT ref.add_lookup_value('ref.audit_action', 'consent_changed',       'Consent changed',            11);
SELECT ref.add_lookup_value('ref.audit_action', 'profile_viewed',        'Profile viewed',             12);
SELECT ref.add_lookup_value('ref.audit_action', 'profile_downloaded',    'Profile downloaded',         13);
SELECT ref.add_lookup_value('ref.audit_action', 'identifier_viewed',     'Identifier viewed',          14);
SELECT ref.add_lookup_value('ref.audit_action', 'record_deleted',        'Record deleted',             15);
SELECT ref.add_lookup_value('ref.audit_action', 'data_exported',         'Data exported',              16);
SELECT ref.add_lookup_value('ref.audit_action', 'verification_changed',  'Verification changed',       17);
SELECT ref.add_lookup_value('ref.audit_action', 'payment_refunded',      'Payment refunded',           18);

SELECT ref.create_lookup('ref.error_severity', 'severity of a logged system error');
SELECT ref.add_lookup_value('ref.error_severity', 'warning',  'Warning',  1);
SELECT ref.add_lookup_value('ref.error_severity', 'error',    'Error',    2);
SELECT ref.add_lookup_value('ref.error_severity', 'critical', 'Critical', 3);

-- ---------------------------------------------------------------------------------------------------
-- app_user: extend the stub with login identifiers
ALTER TABLE admin.app_user
  ADD COLUMN login_email             d_email,
  ADD COLUMN login_phone             d_phone_e164,
  ADD COLUMN login_phone_country_id  bigint,
  ADD COLUMN display_name            d_person_name,
  ADD COLUMN last_login_at           timestamptz,
  ADD CONSTRAINT fk_app_user_login_phone_country_id FOREIGN KEY (login_phone_country_id) REFERENCES ref.country (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT uq_app_user_login_email UNIQUE (login_email),
  ADD CONSTRAINT uq_app_user_login_phone UNIQUE (login_phone),
  ADD CONSTRAINT ck_app_user_login_identifier CHECK (is_system_actor OR login_email IS NOT NULL OR login_phone IS NOT NULL OR deleted_at IS NOT NULL OR user_status_code = 'pending_verification'),
  ADD CONSTRAINT ck_app_user_login_phone_country CHECK ((login_phone IS NULL) = (login_phone_country_id IS NULL));
COMMENT ON COLUMN admin.app_user.login_email IS '[Personal] Login email, lowercase, unique; null: phone-only login, system actor, or account not yet verified';
COMMENT ON COLUMN admin.app_user.login_phone IS '[Personal] Login phone in E.164, unique; null: email-only login or system actor';
COMMENT ON COLUMN admin.app_user.login_phone_country_id IS '[Personal] Country of login_phone; null: no login phone';
COMMENT ON COLUMN admin.app_user.display_name IS '[Personal] Name shown in the UI; null: system actor or not provided (profiles hold the full name)';
COMMENT ON COLUMN admin.app_user.last_login_at IS '[Internal] Last successful login (UTC); null: never logged in';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE admin.user_credential (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id            bigint       NOT NULL,
  password_hash          varchar(255) NOT NULL,
  hash_algorithm_code    d_code       NOT NULL DEFAULT 'argon2id',
  password_changed_at    timestamptz  NOT NULL DEFAULT now(),
  failed_attempt_count   smallint     NOT NULL DEFAULT 0,
  locked_until           timestamptz,
  must_change_password   boolean      NOT NULL DEFAULT false,
  created_at             timestamptz  NOT NULL DEFAULT now(),
  created_by             bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz  NOT NULL DEFAULT now(),
  updated_by             bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_user_credential PRIMARY KEY (id),
  CONSTRAINT uq_user_credential_app_user_id UNIQUE (app_user_id),
  CONSTRAINT fk_user_credential_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_user_credential_hash_algorithm_code FOREIGN KEY (hash_algorithm_code) REFERENCES ref.hash_algorithm (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_user_credential_password_hash_format CHECK (password_hash ~ '^\$(argon2id\$v=19\$|2[aby]\$)'),
  CONSTRAINT ck_user_credential_hash_matches_algorithm CHECK ((hash_algorithm_code = 'argon2id') = (password_hash LIKE '$argon2id$%')),
  CONSTRAINT ck_user_credential_failed_attempt_count CHECK (failed_attempt_count BETWEEN 0 AND 100)
);
COMMENT ON TABLE  admin.user_credential IS '[hard-delete] Password credential of a login identity: hash only, one per user (owned by app_user). Restricted grants in M18';
COMMENT ON COLUMN admin.user_credential.app_user_id IS '[Internal] Owner (unique: one credential per user)';
COMMENT ON COLUMN admin.user_credential.password_hash IS '[Sensitive] PHC-format hash ($argon2id$v=19$...); the password itself is never stored';
COMMENT ON COLUMN admin.user_credential.hash_algorithm_code IS '[Internal] Algorithm of password_hash; default argon2id';
COMMENT ON COLUMN admin.user_credential.password_changed_at IS '[Internal] When the password was last set (UTC)';
COMMENT ON COLUMN admin.user_credential.failed_attempt_count IS '[Internal] Consecutive failed logins, reset on success; default 0';
COMMENT ON COLUMN admin.user_credential.locked_until IS '[Internal] Lockout end after too many failures (UTC); null: not locked';
COMMENT ON COLUMN admin.user_credential.must_change_password IS '[Internal] Force a change at next login; default false';

-- ---------------------------------------------------------------------------------------------------
-- Roles and permissions (actors from docket Section 3)
SELECT ref.create_lookup('admin.app_role', 'actor role (docket Section 3)');
ALTER TABLE admin.app_role ADD COLUMN is_organisation_scoped boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN admin.app_role.is_organisation_scoped IS '[Public] Grants of this role must name an organisation; default false';
SELECT ref.add_lookup_value('admin.app_role', 'super_admin',       'Super admin',               1);
SELECT ref.add_lookup_value('admin.app_role', 'admin',             'Admin',                     2);
SELECT ref.add_lookup_value('admin.app_role', 'account_admin',     'Account admin',             3);
SELECT ref.add_lookup_value('admin.app_role', 'guest',             'Guest',                     4);
SELECT ref.add_lookup_value('admin.app_role', 'candidate',         'Candidate',                 5);
SELECT ref.add_lookup_value('admin.app_role', 'employer',          'Employer',                  6);
SELECT ref.add_lookup_value('admin.app_role', 'recruiter',         'Recruiter',                 7);
SELECT ref.add_lookup_value('admin.app_role', 'consultant',        'Consultant',                8);
SELECT ref.add_lookup_value('admin.app_role', 'placement_officer', 'Placement officer (TPO)',   9);
SELECT ref.add_lookup_value('admin.app_role', 'gig_worker',        'Gig worker',                10);
UPDATE admin.app_role SET is_organisation_scoped = code IN ('account_admin', 'employer', 'recruiter', 'placement_officer');

SELECT ref.create_lookup('admin.permission', 'action a role may perform');
SELECT ref.add_lookup_value('admin.permission', 'job_post',             'Post and edit job requirements',      1);
SELECT ref.add_lookup_value('admin.permission', 'job_publish',          'Publish job requirements',            2);
SELECT ref.add_lookup_value('admin.permission', 'application_manage',   'Move applications through the pipeline', 3);
SELECT ref.add_lookup_value('admin.permission', 'candidate_search',     'Search candidate profiles',           4);
SELECT ref.add_lookup_value('admin.permission', 'profile_download',     'Download candidate profiles',         5);
SELECT ref.add_lookup_value('admin.permission', 'outreach_send',        'Send bulk outreach',                  6);
SELECT ref.add_lookup_value('admin.permission', 'sourcing_request',     'Request to source for a job',         7);
SELECT ref.add_lookup_value('admin.permission', 'profile_edit_own',     'Edit own candidate profile',          8);
SELECT ref.add_lookup_value('admin.permission', 'job_apply',            'Apply to jobs',                       9);
SELECT ref.add_lookup_value('admin.permission', 'gig_apply',            'Apply to gig requests',               10);
SELECT ref.add_lookup_value('admin.permission', 'gig_post',             'Post gig requests',                   11);
SELECT ref.add_lookup_value('admin.permission', 'organisation_manage',  'Manage organisation and recruiters',  12);
SELECT ref.add_lookup_value('admin.permission', 'wallet_recharge',      'Recharge the wallet',                 13);
SELECT ref.add_lookup_value('admin.permission', 'campus_drive_manage',  'Run campus drives',                   14);
SELECT ref.add_lookup_value('admin.permission', 'user_block',           'Block users and companies',           15);
SELECT ref.add_lookup_value('admin.permission', 'platform_admin',       'Administer the platform',             16);
SELECT ref.add_lookup_value('admin.permission', 'audit_read',           'Read the audit trail',                17);

CREATE TABLE admin.app_role_permission (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  app_role_code    d_code      NOT NULL,
  permission_code  d_code      NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_app_role_permission PRIMARY KEY (id),
  CONSTRAINT uq_app_role_permission_app_role_code_permission_code UNIQUE (app_role_code, permission_code),
  CONSTRAINT fk_app_role_permission_app_role_code FOREIGN KEY (app_role_code) REFERENCES admin.app_role (code) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_app_role_permission_permission_code FOREIGN KEY (permission_code) REFERENCES admin.permission (code) ON UPDATE NO ACTION ON DELETE CASCADE
);
COMMENT ON TABLE  admin.app_role_permission IS '[hard-delete] Permission granted to a role (junction, owned by both sides)';
COMMENT ON COLUMN admin.app_role_permission.app_role_code IS '[Public] Role';
COMMENT ON COLUMN admin.app_role_permission.permission_code IS '[Public] Permission held by the role';

INSERT INTO admin.app_role_permission (app_role_code, permission_code)
SELECT r, p FROM (VALUES
  ('candidate', 'profile_edit_own'), ('candidate', 'job_apply'), ('candidate', 'user_block'),
  ('gig_worker', 'gig_apply'), ('gig_worker', 'user_block'),
  ('employer', 'job_post'), ('employer', 'job_publish'), ('employer', 'application_manage'), ('employer', 'candidate_search'),
  ('employer', 'profile_download'), ('employer', 'outreach_send'), ('employer', 'gig_post'), ('employer', 'wallet_recharge'),
  ('employer', 'organisation_manage'),
  ('recruiter', 'job_post'), ('recruiter', 'application_manage'), ('recruiter', 'candidate_search'), ('recruiter', 'profile_download'),
  ('recruiter', 'outreach_send'),
  ('consultant', 'sourcing_request'), ('consultant', 'candidate_search'), ('consultant', 'outreach_send'),
  ('placement_officer', 'campus_drive_manage'), ('placement_officer', 'candidate_search'),
  ('account_admin', 'organisation_manage'), ('account_admin', 'wallet_recharge'),
  ('admin', 'platform_admin'), ('admin', 'user_block'), ('admin', 'audit_read'),
  ('super_admin', 'platform_admin'), ('super_admin', 'audit_read'), ('super_admin', 'user_block')) v(r, p);

-- Effective-dated role grant. Out of scope (docket Section 3): sub-roles inside an employer organisation.
-- Extension path: add permission rows and grant org-scoped roles per organisation; no table change needed.
CREATE TABLE admin.user_role (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id      bigint      NOT NULL,
  app_role_code    d_code      NOT NULL,
  organisation_id  bigint,
  valid_period     tstzrange   NOT NULL DEFAULT tstzrange(now(), NULL, '[)'),
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_user_role PRIMARY KEY (id),
  CONSTRAINT fk_user_role_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_user_role_app_role_code FOREIGN KEY (app_role_code) REFERENCES admin.app_role (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_user_role_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_user_role_valid_period CHECK (NOT isempty(valid_period) AND lower(valid_period) IS NOT NULL),
  -- the same role cannot be held twice at the same time for the same scope
  CONSTRAINT ex_user_role_no_overlap EXCLUDE USING gist (
    app_user_id WITH =, app_role_code WITH =, (coalesce(organisation_id, 0)) WITH =, valid_period WITH &&)
);
CREATE INDEX idx_user_role_organisation_id ON admin.user_role (organisation_id) WHERE organisation_id IS NOT NULL;
COMMENT ON TABLE  admin.user_role IS '[hard-delete] Role held by a user, optionally scoped to an organisation, over an effective period; revocation closes the period (history kept)';
COMMENT ON COLUMN admin.user_role.app_user_id IS '[Internal] User holding the role';
COMMENT ON COLUMN admin.user_role.app_role_code IS '[Internal] Role held';
COMMENT ON COLUMN admin.user_role.organisation_id IS '[Internal] Organisation the role applies to; null: platform-wide role (candidate, admin)';
COMMENT ON COLUMN admin.user_role.valid_period IS '[Internal] Effective period [from, to) in UTC; open upper bound = still held; default from now';

-- org-scoped roles must name an organisation, others must not
CREATE FUNCTION admin.check_user_role_scope() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  IF (SELECT is_organisation_scoped FROM admin.app_role WHERE code = NEW.app_role_code) <> (NEW.organisation_id IS NOT NULL) THEN
    RAISE EXCEPTION 'trg_user_role_scope: role % % an organisation', NEW.app_role_code,
      CASE WHEN NEW.organisation_id IS NULL THEN 'requires' ELSE 'must not name' END
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_user_role_scope BEFORE INSERT OR UPDATE OF app_role_code, organisation_id ON admin.user_role
  FOR EACH ROW EXECUTE FUNCTION admin.check_user_role_scope();

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE admin.consent_record (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id           bigint      NOT NULL,
  consent_purpose_code  d_code      NOT NULL,
  is_granted            boolean     NOT NULL DEFAULT false,
  policy_version        varchar(20) NOT NULL,
  recorded_at           timestamptz NOT NULL DEFAULT now(),
  client_ip_masked      varchar(45),
  created_at            timestamptz NOT NULL DEFAULT now(),
  created_by            bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_consent_record PRIMARY KEY (id),
  CONSTRAINT fk_consent_record_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_consent_record_consent_purpose_code FOREIGN KEY (consent_purpose_code) REFERENCES ref.consent_purpose (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_consent_record_app_user_id ON admin.consent_record (app_user_id, consent_purpose_code, recorded_at DESC);
COMMENT ON TABLE  admin.consent_record IS '[append-only] Consent given or withdrawn; the latest row per user and purpose is the current state (withdrawal is a new row)';
COMMENT ON COLUMN admin.consent_record.app_user_id IS '[Internal] User giving or withdrawing consent';
COMMENT ON COLUMN admin.consent_record.consent_purpose_code IS '[Internal] Purpose';
COMMENT ON COLUMN admin.consent_record.is_granted IS '[Internal] true = given, false = withdrawn; default false (no consent unless explicitly given)';
COMMENT ON COLUMN admin.consent_record.policy_version IS '[Internal] Version of the policy text agreed to, max 20';
COMMENT ON COLUMN admin.consent_record.recorded_at IS '[Internal] When consent was captured (UTC)';
COMMENT ON COLUMN admin.consent_record.client_ip_masked IS '[Personal] Client IP with the last octet/group masked; null: captured offline or by an admin';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE admin.block_list (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  blocker_app_user_id      bigint       NOT NULL,
  blocked_app_user_id      bigint,
  blocked_organisation_id  bigint,
  block_reason             varchar(300),
  created_at               timestamptz  NOT NULL DEFAULT now(),
  created_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz  NOT NULL DEFAULT now(),
  updated_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  deleted_at               timestamptz,
  CONSTRAINT pk_block_list PRIMARY KEY (id),
  CONSTRAINT fk_block_list_blocker_app_user_id FOREIGN KEY (blocker_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_block_list_blocked_app_user_id FOREIGN KEY (blocked_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_block_list_blocked_organisation_id FOREIGN KEY (blocked_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_block_list_single_target CHECK (num_nonnulls(blocked_app_user_id, blocked_organisation_id) = 1),
  CONSTRAINT ck_block_list_not_self CHECK (blocked_app_user_id IS DISTINCT FROM blocker_app_user_id)
);
CREATE UNIQUE INDEX uq_block_list_active_user_pair ON admin.block_list (blocker_app_user_id, blocked_app_user_id)
  WHERE blocked_app_user_id IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_block_list_active_organisation_pair ON admin.block_list (blocker_app_user_id, blocked_organisation_id)
  WHERE blocked_organisation_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_block_list_blocked_app_user_id ON admin.block_list (blocked_app_user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_block_list_blocked_organisation_id ON admin.block_list (blocked_organisation_id) WHERE deleted_at IS NULL;
COMMENT ON TABLE  admin.block_list IS '[soft-delete] A user (usually a candidate) blocks one user or one organisation; unblocking sets deleted_at so history is kept. RLS in M18 hides the blocker from the blocked party';
COMMENT ON COLUMN admin.block_list.blocker_app_user_id IS '[Internal] User who blocked';
COMMENT ON COLUMN admin.block_list.blocked_app_user_id IS '[Internal] Blocked recruiter, consultant or employer user; null: an organisation is blocked instead';
COMMENT ON COLUMN admin.block_list.blocked_organisation_id IS '[Internal] Blocked company; null: a single user is blocked instead';
COMMENT ON COLUMN admin.block_list.block_reason IS '[Personal] Optional note by the blocker, max 300; null: no reason given';

-- ---------------------------------------------------------------------------------------------------
-- Audit trail and error log (append-only; written through audit.log_event)
CREATE TABLE audit.audit_event (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  actor_app_user_id   bigint,
  audit_action_code   d_code       NOT NULL,
  subject_table       varchar(130) NOT NULL,
  subject_id          bigint,
  event_detail        jsonb,
  client_ip_masked    varchar(45),
  occurred_at         timestamptz  NOT NULL DEFAULT now(),
  created_at          timestamptz  NOT NULL DEFAULT now(),
  created_by          bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_audit_event PRIMARY KEY (id),
  CONSTRAINT fk_audit_event_actor_app_user_id FOREIGN KEY (actor_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_audit_event_audit_action_code FOREIGN KEY (audit_action_code) REFERENCES ref.audit_action (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_audit_event_subject_table_format CHECK (subject_table ~ '^[a-z_]+\.[a-z0-9_]+$')
);
CREATE INDEX idx_audit_event_actor_app_user_id ON audit.audit_event (actor_app_user_id, occurred_at);
CREATE INDEX idx_audit_event_subject ON audit.audit_event (subject_table, subject_id, occurred_at);
CREATE INDEX idx_audit_event_audit_action_code ON audit.audit_event (audit_action_code, occurred_at);
COMMENT ON TABLE  audit.audit_event IS '[append-only] Audit trail of sensitive actions (RG4); application users cannot update or delete it (trigger + revoked grants). Retention: 7 years';
COMMENT ON COLUMN audit.audit_event.actor_app_user_id IS '[Internal] User who acted; null: unauthenticated actor (failed login with an unknown identifier)';
COMMENT ON COLUMN audit.audit_event.audit_action_code IS '[Internal] Action performed';
COMMENT ON COLUMN audit.audit_event.subject_table IS '[Internal] schema.table of the record acted on';
COMMENT ON COLUMN audit.audit_event.subject_id IS '[Internal] id of the record acted on; nofk: polymorphic reference across tables (subject_table names it); null: action has no single subject';
COMMENT ON COLUMN audit.audit_event.event_detail IS '[Internal] Action-specific detail (old/new values, limits); never message bodies or secrets; null: none';
COMMENT ON COLUMN audit.audit_event.client_ip_masked IS '[Personal] Client IP with the last octet/group masked; null: server-side or batch action';
COMMENT ON COLUMN audit.audit_event.occurred_at IS '[Internal] When the action happened (UTC)';

CREATE TABLE audit.error_log (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  error_severity_code   d_code        NOT NULL,
  error_code            varchar(20)   NOT NULL,
  error_message         varchar(2000) NOT NULL,
  error_context         varchar(4000),
  app_user_id           bigint,
  occurred_at           timestamptz   NOT NULL DEFAULT now(),
  created_at            timestamptz   NOT NULL DEFAULT now(),
  created_by            bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_error_log PRIMARY KEY (id),
  CONSTRAINT fk_error_log_error_severity_code FOREIGN KEY (error_severity_code) REFERENCES ref.error_severity (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_error_log_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_error_log_occurred_at ON audit.error_log (occurred_at, error_severity_code);
COMMENT ON TABLE  audit.error_log IS '[append-only] System errors (application and integration). Retention: 90 days';
COMMENT ON COLUMN audit.error_log.error_severity_code IS '[Internal] warning, error, critical';
COMMENT ON COLUMN audit.error_log.error_code IS '[Internal] SQLSTATE or application error code, max 20; nofk: open-ended codes raised by PostgreSQL and services, not a fixed set';
COMMENT ON COLUMN audit.error_log.error_message IS '[Internal] Error message with personal data removed, max 2000';
COMMENT ON COLUMN audit.error_log.error_context IS '[Internal] Stack or request context, max 4000; null: none captured';
COMMENT ON COLUMN audit.error_log.app_user_id IS '[Internal] User whose request failed; null: background job or anonymous request';
COMMENT ON COLUMN audit.error_log.occurred_at IS '[Internal] When the error happened (UTC)';

-- The one write path for the audit trail. SECURITY DEFINER so it works even where the caller cannot insert directly;
-- the actor is always the session actor (app.current_user_id), never a parameter, so callers cannot forge it.
CREATE FUNCTION audit.log_event(p_action text, p_subject_table text, p_subject_id bigint DEFAULT NULL,
                                p_detail jsonb DEFAULT NULL, p_client_ip_masked text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_id    bigint;
  v_actor bigint := public.current_actor_id();
BEGIN
  INSERT INTO audit.audit_event (actor_app_user_id, audit_action_code, subject_table, subject_id, event_detail, client_ip_masked, created_by)
  VALUES (v_actor, p_action, p_subject_table, p_subject_id, p_detail, p_client_ip_masked, coalesce(v_actor, 1))
  RETURNING id INTO v_id;
  RETURN v_id;
END
$$;
REVOKE ALL ON FUNCTION audit.log_event(text, text, bigint, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.log_event(text, text, bigint, jsonb, text) TO talentra_app, talentra_integration;

-- Sensitive admin changes write the audit trail automatically
CREATE FUNCTION admin.audit_sensitive_change() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  IF TG_TABLE_NAME = 'user_role' THEN
    PERFORM audit.log_event(CASE WHEN TG_OP = 'INSERT' THEN 'role_granted' ELSE 'role_revoked' END,
                            'admin.user_role', NEW.id,
                            jsonb_build_object('app_user_id', NEW.app_user_id, 'role', NEW.app_role_code,
                                               'organisation_id', NEW.organisation_id, 'valid_period', NEW.valid_period::text));
  ELSIF TG_TABLE_NAME = 'block_list' THEN
    PERFORM audit.log_event(CASE WHEN TG_OP = 'INSERT' THEN 'block_added' ELSE 'block_removed' END,
                            'admin.block_list', NEW.id, NULL);
  ELSIF TG_TABLE_NAME = 'user_credential' THEN
    PERFORM audit.log_event('credential_changed', 'admin.user_credential', NEW.id,
                            jsonb_build_object('app_user_id', NEW.app_user_id));
  ELSIF TG_TABLE_NAME = 'consent_record' THEN
    PERFORM audit.log_event('consent_changed', 'admin.consent_record', NEW.id,
                            jsonb_build_object('purpose', NEW.consent_purpose_code, 'granted', NEW.is_granted));
  END IF;
  RETURN NULL;
END
$$;
CREATE TRIGGER trg_user_role_audit AFTER INSERT OR UPDATE OF valid_period ON admin.user_role
  FOR EACH ROW EXECUTE FUNCTION admin.audit_sensitive_change();
CREATE TRIGGER trg_block_list_audit AFTER INSERT OR UPDATE OF deleted_at ON admin.block_list
  FOR EACH ROW EXECUTE FUNCTION admin.audit_sensitive_change();
CREATE TRIGGER trg_user_credential_audit AFTER INSERT OR UPDATE OF password_hash ON admin.user_credential
  FOR EACH ROW EXECUTE FUNCTION admin.audit_sensitive_change();
CREATE TRIGGER trg_consent_record_audit AFTER INSERT ON admin.consent_record
  FOR EACH ROW EXECUTE FUNCTION admin.audit_sensitive_change();
