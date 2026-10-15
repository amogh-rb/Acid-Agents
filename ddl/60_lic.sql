-- Licences, seats, devices and sessions (schemas lic, app). Owner A. Phase 3: M11-M14 (B36, B39, B42, B45).
-- Entities and relationships: docs/phase3/lic_entities.md, lic_relationships.md.
-- Rule group 9:
--   * every licence has max_users and max_devices_per_user, both CHECK > 0
--   * seats: active seats per licence <= max_users, enforced by trg_licence_seat_limit under a lock on the licence row
--   * device limit at login: app.start_session locks the user's seat row (SELECT ... FOR UPDATE), counts the user's
--     active sessions (ended_at IS NULL AND expires_at > now(); partial index), then either starts the session or
--     records login_attempt + audit 'device_limit_exceeded' and RETURNS a rejection (so the audit row commits)
--   * a session is released by app.end_session (logout), app.revoke_session / app.revoke_device (audited) and
--     app.expire_idle_sessions (idle timeout or hard expiry); expired or revoked sessions never count

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
SELECT ref.create_lookup('ref.licence_status', 'licence status');
SELECT ref.add_lookup_value('ref.licence_status', 'active',    'Active',    1);
SELECT ref.add_lookup_value('ref.licence_status', 'suspended', 'Suspended', 2);
SELECT ref.add_lookup_value('ref.licence_status', 'expired',   'Expired',   3);

SELECT ref.create_lookup('ref.device_platform', 'platform of a registered device');
SELECT ref.add_lookup_value('ref.device_platform', 'web',     'Web browser', 1);
SELECT ref.add_lookup_value('ref.device_platform', 'android', 'Android',     2);
SELECT ref.add_lookup_value('ref.device_platform', 'ios',     'iOS',         3);
SELECT ref.add_lookup_value('ref.device_platform', 'desktop', 'Desktop app', 4);

SELECT ref.create_lookup('ref.session_end_reason', 'why a session ended');
SELECT ref.add_lookup_value('ref.session_end_reason', 'logout',         'Logged out',       1);
SELECT ref.add_lookup_value('ref.session_end_reason', 'revoked',        'Revoked',          2);
SELECT ref.add_lookup_value('ref.session_end_reason', 'device_revoked', 'Device revoked',   3);
SELECT ref.add_lookup_value('ref.session_end_reason', 'idle_timeout',   'Idle timeout',     4);
SELECT ref.add_lookup_value('ref.session_end_reason', 'expired',        'Expired',          5);

SELECT ref.create_lookup('ref.login_outcome', 'outcome of a login attempt');
SELECT ref.add_lookup_value('ref.login_outcome', 'started',         'Session started',         1);
SELECT ref.add_lookup_value('ref.login_outcome', 'device_limit',    'Device limit reached',    2);
SELECT ref.add_lookup_value('ref.login_outcome', 'no_seat',         'No licence seat',         3);
SELECT ref.add_lookup_value('ref.login_outcome', 'licence_inactive', 'Licence not active',     4);
SELECT ref.add_lookup_value('ref.login_outcome', 'device_revoked',  'Device revoked',          5);
SELECT ref.add_lookup_value('ref.login_outcome', 'bad_credentials', 'Wrong credentials',       6);
SELECT ref.add_lookup_value('ref.login_outcome', 'locked',          'Account locked',          7);

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE lic.licence (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  account_id             bigint       NOT NULL,
  licence_name           varchar(150) NOT NULL,
  max_users              integer      NOT NULL,
  max_devices_per_user   integer      NOT NULL,
  session_ttl_minutes    integer      NOT NULL DEFAULT 720,
  idle_timeout_minutes   integer      NOT NULL DEFAULT 60,
  licence_status_code    d_code       NOT NULL DEFAULT 'active',
  created_at             timestamptz  NOT NULL DEFAULT now(),
  created_by             bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz  NOT NULL DEFAULT now(),
  updated_by             bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_licence PRIMARY KEY (id),
  CONSTRAINT fk_licence_account_id FOREIGN KEY (account_id) REFERENCES org.account (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_licence_licence_status_code FOREIGN KEY (licence_status_code) REFERENCES ref.licence_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_licence_max_users_positive CHECK (max_users > 0),
  CONSTRAINT ck_licence_max_devices_per_user_positive CHECK (max_devices_per_user > 0),
  CONSTRAINT ck_licence_session_ttl_minutes CHECK (session_ttl_minutes > 0),
  CONSTRAINT ck_licence_idle_timeout_minutes CHECK (idle_timeout_minutes > 0 AND idle_timeout_minutes <= session_ttl_minutes)
);
CREATE INDEX idx_licence_account_id ON lic.licence (account_id);
COMMENT ON TABLE  lic.licence IS '[hard-delete] Subscription licence of an account: users allowed and devices allowed per user (RG9). Limits are copied from the plan when a subscription starts and may be raised per licence';
COMMENT ON COLUMN lic.licence.account_id IS '[Internal] Licensed account';
COMMENT ON COLUMN lic.licence.licence_name IS '[Internal] Display name, max 150';
COMMENT ON COLUMN lic.licence.max_users IS '[Internal] Seats allowed (positive)';
COMMENT ON COLUMN lic.licence.max_devices_per_user IS '[Internal] Concurrent active sessions allowed per user (positive)';
COMMENT ON COLUMN lic.licence.session_ttl_minutes IS '[Internal] Hard session lifetime; default 720 (12 h)';
COMMENT ON COLUMN lic.licence.idle_timeout_minutes IS '[Internal] Idle time after which app.expire_idle_sessions ends a session; default 60';
COMMENT ON COLUMN lic.licence.licence_status_code IS '[Internal] active, suspended, expired; default active';

CREATE TABLE lic.licence_seat (
  id           bigint GENERATED ALWAYS AS IDENTITY,
  licence_id   bigint      NOT NULL,
  app_user_id  bigint      NOT NULL,
  assigned_at  timestamptz NOT NULL DEFAULT now(),
  released_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_licence_seat PRIMARY KEY (id),
  CONSTRAINT uq_licence_seat_id_app_user_id UNIQUE (id, app_user_id),
  CONSTRAINT fk_licence_seat_licence_id FOREIGN KEY (licence_id) REFERENCES lic.licence (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_licence_seat_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_licence_seat_time_range CHECK (released_at IS NULL OR released_at >= assigned_at)
);
-- one active seat per user (on any licence) and per licence/user pair
CREATE UNIQUE INDEX uq_licence_seat_active_user ON lic.licence_seat (app_user_id) WHERE released_at IS NULL;
CREATE INDEX idx_licence_seat_licence_id ON lic.licence_seat (licence_id) WHERE released_at IS NULL;
COMMENT ON TABLE  lic.licence_seat IS '[hard-delete] Seat of a licence allocated to a user; releasing sets released_at (history kept). Active seats per licence <= max_users (trg_licence_seat_limit)';
COMMENT ON COLUMN lic.licence_seat.licence_id IS '[Internal] Licence the seat belongs to';
COMMENT ON COLUMN lic.licence_seat.app_user_id IS '[Internal] User holding the seat (one active seat per user)';
COMMENT ON COLUMN lic.licence_seat.assigned_at IS '[Internal] Allocation instant (UTC)';
COMMENT ON COLUMN lic.licence_seat.released_at IS '[Internal] Release instant (UTC); null: seat in use';

CREATE FUNCTION lic.check_licence_seat_limit() RETURNS trigger
LANGUAGE plpgsql AS
$$
DECLARE
  v_max  integer;
  v_used integer;
BEGIN
  IF NEW.released_at IS NOT NULL THEN
    RETURN NEW;
  END IF;
  -- serialise seat allocation per licence: concurrent allocations queue on this row lock
  SELECT max_users INTO v_max FROM lic.licence WHERE id = NEW.licence_id FOR UPDATE;
  SELECT count(*) INTO v_used FROM lic.licence_seat
   WHERE licence_id = NEW.licence_id AND released_at IS NULL AND id IS DISTINCT FROM NEW.id;
  IF v_used >= v_max THEN
    RAISE EXCEPTION 'trg_licence_seat_limit: licence % already uses % of % seats', NEW.licence_id, v_used, v_max
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_licence_seat_limit BEFORE INSERT OR UPDATE OF released_at, licence_id ON lic.licence_seat
  FOR EACH ROW EXECUTE FUNCTION lic.check_licence_seat_limit();

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE lic.registered_device (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id              bigint       NOT NULL,
  device_fingerprint_hash  bytea        NOT NULL,
  device_platform_code     d_code       NOT NULL DEFAULT 'web',
  device_label             varchar(100),
  first_seen_at            timestamptz  NOT NULL DEFAULT now(),
  last_seen_at             timestamptz  NOT NULL DEFAULT now(),
  revoked_at               timestamptz,
  created_at               timestamptz  NOT NULL DEFAULT now(),
  created_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz  NOT NULL DEFAULT now(),
  updated_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_registered_device PRIMARY KEY (id),
  CONSTRAINT uq_registered_device_app_user_id_fingerprint UNIQUE (app_user_id, device_fingerprint_hash),
  CONSTRAINT uq_registered_device_id_app_user_id UNIQUE (id, app_user_id),
  CONSTRAINT fk_registered_device_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_registered_device_device_platform_code FOREIGN KEY (device_platform_code) REFERENCES ref.device_platform (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_registered_device_fingerprint_length CHECK (octet_length(device_fingerprint_hash) = 32),
  CONSTRAINT ck_registered_device_seen_range CHECK (last_seen_at >= first_seen_at)
);
COMMENT ON TABLE  lic.registered_device IS '[hard-delete] Device a user has logged in from (owned by app_user); revoking sets revoked_at and ends its sessions (audited)';
COMMENT ON COLUMN lic.registered_device.app_user_id IS '[Internal] Device owner';
COMMENT ON COLUMN lic.registered_device.device_fingerprint_hash IS '[Sensitive] SHA-256 of the client device fingerprint; the raw fingerprint is never stored';
COMMENT ON COLUMN lic.registered_device.device_platform_code IS '[Internal] web, android, ios, desktop; default web';
COMMENT ON COLUMN lic.registered_device.device_label IS '[Personal] User-visible name (Priya''s phone), max 100; null: not named';
COMMENT ON COLUMN lic.registered_device.first_seen_at IS '[Internal] First login from the device (UTC)';
COMMENT ON COLUMN lic.registered_device.last_seen_at IS '[Internal] Latest login from the device (UTC)';
COMMENT ON COLUMN lic.registered_device.revoked_at IS '[Internal] When the device was revoked (UTC); null: device allowed';

CREATE TABLE lic.login_session (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id              bigint       NOT NULL,
  registered_device_id     bigint       NOT NULL,
  licence_seat_id          bigint       NOT NULL,
  session_token_hash       bytea        NOT NULL,
  started_at               timestamptz  NOT NULL DEFAULT now(),
  last_activity_at         timestamptz  NOT NULL DEFAULT now(),
  expires_at               timestamptz  NOT NULL,
  ended_at                 timestamptz,
  session_end_reason_code  d_code,
  created_at               timestamptz  NOT NULL DEFAULT now(),
  created_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz  NOT NULL DEFAULT now(),
  updated_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_login_session PRIMARY KEY (id),
  CONSTRAINT uq_login_session_session_token_hash UNIQUE (session_token_hash),
  CONSTRAINT fk_login_session_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  -- the device and the seat must belong to the session's user
  CONSTRAINT fk_login_session_device FOREIGN KEY (registered_device_id, app_user_id)
    REFERENCES lic.registered_device (id, app_user_id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_login_session_seat FOREIGN KEY (licence_seat_id, app_user_id)
    REFERENCES lic.licence_seat (id, app_user_id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_login_session_registered_device_id FOREIGN KEY (registered_device_id) REFERENCES lic.registered_device (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_login_session_licence_seat_id FOREIGN KEY (licence_seat_id) REFERENCES lic.licence_seat (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_login_session_session_end_reason_code FOREIGN KEY (session_end_reason_code) REFERENCES ref.session_end_reason (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_login_session_token_hash_length CHECK (octet_length(session_token_hash) = 32),
  CONSTRAINT ck_login_session_time_range CHECK (expires_at > started_at AND last_activity_at >= started_at
                                                AND (ended_at IS NULL OR ended_at >= started_at)),
  CONSTRAINT ck_login_session_end_pair CHECK ((ended_at IS NULL) = (session_end_reason_code IS NULL))
);
-- the device-limit count reads only open sessions; the index stays small as history grows
CREATE INDEX idx_login_session_active_user ON lic.login_session (app_user_id, expires_at) WHERE ended_at IS NULL;
CREATE INDEX idx_login_session_registered_device_id ON lic.login_session (registered_device_id) WHERE ended_at IS NULL;
CREATE INDEX idx_login_session_licence_seat_id ON lic.login_session (licence_seat_id);
COMMENT ON TABLE  lic.login_session IS '[hard-delete] [api-write] Login session on a device under a licence seat (RG9: device, start, last activity, end). Active = ended_at IS NULL AND expires_at > now(). Retention: 90 days after end';
COMMENT ON COLUMN lic.login_session.app_user_id IS '[Internal] Session owner';
COMMENT ON COLUMN lic.login_session.registered_device_id IS '[Internal] Device used (must belong to the user)';
COMMENT ON COLUMN lic.login_session.licence_seat_id IS '[Internal] Seat the session counts against (must belong to the user)';
COMMENT ON COLUMN lic.login_session.session_token_hash IS '[Sensitive] SHA-256 of the session token; the token itself is never stored';
COMMENT ON COLUMN lic.login_session.started_at IS '[Internal] Session start (UTC)';
COMMENT ON COLUMN lic.login_session.last_activity_at IS '[Internal] Latest request on the session (UTC)';
COMMENT ON COLUMN lic.login_session.expires_at IS '[Internal] Hard expiry (UTC); an expired session no longer counts against the device limit';
COMMENT ON COLUMN lic.login_session.ended_at IS '[Internal] When the session was released (UTC); null: still open';
COMMENT ON COLUMN lic.login_session.session_end_reason_code IS '[Internal] logout, revoked, device_revoked, idle_timeout, expired; null: still open';

CREATE TABLE lic.login_attempt (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id           bigint,
  registered_device_id  bigint,
  login_outcome_code    d_code      NOT NULL,
  attempted_at          timestamptz NOT NULL DEFAULT now(),
  client_ip_masked      varchar(45),
  attempt_detail        jsonb,
  created_at            timestamptz NOT NULL DEFAULT now(),
  created_by            bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_login_attempt PRIMARY KEY (id),
  CONSTRAINT fk_login_attempt_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_login_attempt_registered_device_id FOREIGN KEY (registered_device_id) REFERENCES lic.registered_device (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_login_attempt_login_outcome_code FOREIGN KEY (login_outcome_code) REFERENCES ref.login_outcome (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_login_attempt_app_user_id ON lic.login_attempt (app_user_id, attempted_at);
CREATE INDEX idx_login_attempt_registered_device_id ON lic.login_attempt (registered_device_id) WHERE registered_device_id IS NOT NULL;
COMMENT ON TABLE  lic.login_attempt IS '[append-only] [api-write] Login history: every attempt and its outcome, including device-limit rejections. Retention: 1 year';
COMMENT ON COLUMN lic.login_attempt.app_user_id IS '[Internal] User who tried to log in; null: identifier did not match any account';
COMMENT ON COLUMN lic.login_attempt.registered_device_id IS '[Internal] Device used; null: rejected before the device was registered (unknown user, bad credentials)';
COMMENT ON COLUMN lic.login_attempt.login_outcome_code IS '[Internal] started, device_limit, no_seat, licence_inactive, device_revoked, bad_credentials, locked';
COMMENT ON COLUMN lic.login_attempt.attempted_at IS '[Internal] Attempt instant (UTC)';
COMMENT ON COLUMN lic.login_attempt.client_ip_masked IS '[Personal] Client IP with the last octet/group masked; null: not captured';
COMMENT ON COLUMN lic.login_attempt.attempt_detail IS '[Internal] Outcome detail (limit, active count); null: none';

CREATE TABLE lic.session_revocation (
  id                 bigint GENERATED ALWAYS AS IDENTITY,
  login_session_id   bigint       NOT NULL,
  revocation_reason  varchar(300) NOT NULL,
  revoked_at         timestamptz  NOT NULL DEFAULT now(),
  created_at         timestamptz  NOT NULL DEFAULT now(),
  created_by         bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_session_revocation PRIMARY KEY (id),
  CONSTRAINT uq_session_revocation_login_session_id UNIQUE (login_session_id),
  CONSTRAINT fk_session_revocation_login_session_id FOREIGN KEY (login_session_id) REFERENCES lic.login_session (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  lic.session_revocation IS '[append-only] [api-write] Revocation of a session by an admin or the user (who = created_by); also written to the audit trail';
COMMENT ON COLUMN lic.session_revocation.login_session_id IS '[Internal] Session revoked (once)';
COMMENT ON COLUMN lic.session_revocation.revocation_reason IS '[Internal] Why, max 300';
COMMENT ON COLUMN lic.session_revocation.revoked_at IS '[Internal] Revocation instant (UTC)';

-- ---------------------------------------------------------------------------------------------------
-- Session API (B45). Called with SET LOCAL app.current_user_id = <user>.
CREATE FUNCTION app.start_session(p_app_user_id bigint, p_device_fingerprint_hash bytea, p_session_token_hash bytea,
                                  p_device_platform_code text DEFAULT 'web', p_client_ip_masked text DEFAULT NULL)
RETURNS TABLE (outcome text, login_session_id bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_seat      lic.licence_seat;
  v_licence   lic.licence;
  v_device    lic.registered_device;
  v_active    integer;
  v_session   bigint;
BEGIN
  -- 1. lock the user's seat row: concurrent logins of the same user queue here
  SELECT * INTO v_seat FROM lic.licence_seat
   WHERE app_user_id = p_app_user_id AND released_at IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO lic.login_attempt (app_user_id, login_outcome_code, client_ip_masked) VALUES (p_app_user_id, 'no_seat', p_client_ip_masked);
    RETURN QUERY SELECT 'no_seat'::text, NULL::bigint;
    RETURN;
  END IF;
  SELECT * INTO v_licence FROM lic.licence WHERE id = v_seat.licence_id;
  IF v_licence.licence_status_code <> 'active' THEN
    INSERT INTO lic.login_attempt (app_user_id, login_outcome_code, client_ip_masked) VALUES (p_app_user_id, 'licence_inactive', p_client_ip_masked);
    RETURN QUERY SELECT 'licence_inactive'::text, NULL::bigint;
    RETURN;
  END IF;

  -- 2. register or recognise the device
  INSERT INTO lic.registered_device (app_user_id, device_fingerprint_hash, device_platform_code)
  VALUES (p_app_user_id, p_device_fingerprint_hash, p_device_platform_code)
  ON CONFLICT (app_user_id, device_fingerprint_hash) DO UPDATE SET last_seen_at = now()
  RETURNING * INTO v_device;
  IF v_device.revoked_at IS NOT NULL THEN
    INSERT INTO lic.login_attempt (app_user_id, registered_device_id, login_outcome_code, client_ip_masked)
    VALUES (p_app_user_id, v_device.id, 'device_revoked', p_client_ip_masked);
    RETURN QUERY SELECT 'device_revoked'::text, NULL::bigint;
    RETURN;
  END IF;

  -- 3. count active sessions (expired or ended ones do not count)
  SELECT count(*) INTO v_active FROM lic.login_session s
   WHERE s.app_user_id = p_app_user_id AND s.ended_at IS NULL AND s.expires_at > now();
  IF v_active >= v_licence.max_devices_per_user THEN
    INSERT INTO lic.login_attempt (app_user_id, registered_device_id, login_outcome_code, client_ip_masked, attempt_detail)
    VALUES (p_app_user_id, v_device.id, 'device_limit', p_client_ip_masked,
            jsonb_build_object('limit', v_licence.max_devices_per_user, 'active', v_active));
    PERFORM audit.log_event('device_limit_exceeded', 'lic.licence_seat', v_seat.id,
                            jsonb_build_object('app_user_id', p_app_user_id, 'limit', v_licence.max_devices_per_user,
                                               'active', v_active, 'registered_device_id', v_device.id),
                            p_client_ip_masked);
    RETURN QUERY SELECT 'device_limit'::text, NULL::bigint;
    RETURN;
  END IF;

  -- 4. start the session
  INSERT INTO lic.login_session (app_user_id, registered_device_id, licence_seat_id, session_token_hash, expires_at)
  VALUES (p_app_user_id, v_device.id, v_seat.id, p_session_token_hash, now() + make_interval(mins => v_licence.session_ttl_minutes))
  RETURNING id INTO v_session;
  INSERT INTO lic.login_attempt (app_user_id, registered_device_id, login_outcome_code, client_ip_masked)
  VALUES (p_app_user_id, v_device.id, 'started', p_client_ip_masked);
  UPDATE admin.app_user SET last_login_at = now() WHERE id = p_app_user_id;
  RETURN QUERY SELECT 'started'::text, v_session;
END
$$;

CREATE FUNCTION app.end_session(p_login_session_id bigint, p_reason text DEFAULT 'logout') RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
BEGIN
  UPDATE lic.login_session SET ended_at = now(), session_end_reason_code = p_reason
   WHERE id = p_login_session_id AND ended_at IS NULL;
  RETURN FOUND;
END
$$;

CREATE FUNCTION app.revoke_session(p_login_session_id bigint, p_reason text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
BEGIN
  UPDATE lic.login_session SET ended_at = now(), session_end_reason_code = 'revoked'
   WHERE id = p_login_session_id AND ended_at IS NULL;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  INSERT INTO lic.session_revocation (login_session_id, revocation_reason) VALUES (p_login_session_id, p_reason);
  PERFORM audit.log_event('session_revoked', 'lic.login_session', p_login_session_id, jsonb_build_object('reason', p_reason));
  RETURN true;
END
$$;

CREATE FUNCTION app.revoke_device(p_registered_device_id bigint, p_reason text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_ended integer;
BEGIN
  UPDATE lic.registered_device SET revoked_at = now() WHERE id = p_registered_device_id AND revoked_at IS NULL;
  UPDATE lic.login_session SET ended_at = now(), session_end_reason_code = 'device_revoked'
   WHERE registered_device_id = p_registered_device_id AND ended_at IS NULL;
  GET DIAGNOSTICS v_ended = ROW_COUNT;
  PERFORM audit.log_event('device_revoked', 'lic.registered_device', p_registered_device_id,
                          jsonb_build_object('reason', p_reason, 'sessions_ended', v_ended));
  RETURN v_ended;
END
$$;

-- Scheduled sweep: releases idle and hard-expired sessions so history shows when they ended
CREATE FUNCTION app.expire_idle_sessions() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_count integer;
BEGIN
  UPDATE lic.login_session s
     SET ended_at = now(),
         session_end_reason_code = CASE WHEN s.expires_at <= now() THEN 'expired' ELSE 'idle_timeout' END
    FROM lic.licence_seat st JOIN lic.licence l ON l.id = st.licence_id
   WHERE st.id = s.licence_seat_id AND s.ended_at IS NULL
     AND (s.expires_at <= now() OR s.last_activity_at < now() - make_interval(mins => l.idle_timeout_minutes));
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END
$$;

REVOKE ALL ON FUNCTION app.start_session(bigint, bytea, bytea, text, text), app.end_session(bigint, text),
                       app.revoke_session(bigint, text), app.revoke_device(bigint, text), app.expire_idle_sessions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.start_session(bigint, bytea, bytea, text, text), app.end_session(bigint, text),
                          app.revoke_session(bigint, text), app.revoke_device(bigint, text), app.expire_idle_sessions() TO talentra_app;
