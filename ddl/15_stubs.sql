-- Cross-module stubs (M3). Phase 1 FKs need admin.app_user and org.organisation before their owning modules
-- exist. The stubs hold only an id, a status, the audit columns and what Phase 1 needs. Phase 2 owners extend
-- them with ALTER TABLE in their own files (40_admin.sql, 45_org.sql); no Phase 1 FK needs rework.

SET app.current_user_id = '1';

-- Administration (owner A). One row per login identity; the actor of every created_by / updated_by.
CREATE TABLE admin.app_user (
  id                bigint GENERATED ALWAYS AS IDENTITY,
  user_status_code  d_code      NOT NULL DEFAULT 'pending_verification',
  is_system_actor   boolean     NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        bigint      NOT NULL DEFAULT public.current_actor_id(),
  deleted_at        timestamptz,
  CONSTRAINT pk_app_user PRIMARY KEY (id),
  CONSTRAINT fk_app_user_user_status_code FOREIGN KEY (user_status_code)
    REFERENCES ref.user_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_app_user_system_actor_active CHECK (NOT is_system_actor OR (user_status_code = 'active' AND deleted_at IS NULL))
);
COMMENT ON TABLE  admin.app_user IS '[soft-delete] Login identity (candidate, recruiter, consultant, admin, system). Stub in Phase 1; extended by Administration in M7-M10';
COMMENT ON COLUMN admin.app_user.user_status_code IS '[Internal] Account status; default pending_verification';
COMMENT ON COLUMN admin.app_user.is_system_actor IS '[Internal] true for non-human actors (system, ETL, integrations); default false';

-- System actor: id 1 is referenced by the seed rows of every DDL file. The identity sequence then continues at 2.
INSERT INTO admin.app_user (id, user_status_code, is_system_actor)
  OVERRIDING SYSTEM VALUE VALUES (1, 'active', true);
DO $$ BEGIN PERFORM setval(pg_get_serial_sequence('admin.app_user', 'id'), 1); END $$;

-- Organisation and account (owner B). Employer, client, consultancy or campus.
CREATE TABLE org.organisation (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  organisation_name         varchar(200) NOT NULL,
  organisation_status_code  d_code       NOT NULL DEFAULT 'pending_verification',
  created_at                timestamptz  NOT NULL DEFAULT now(),
  created_by                bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz  NOT NULL DEFAULT now(),
  updated_by                bigint       NOT NULL DEFAULT public.current_actor_id(),
  deleted_at                timestamptz,
  CONSTRAINT pk_organisation PRIMARY KEY (id),
  CONSTRAINT fk_organisation_organisation_status_code FOREIGN KEY (organisation_status_code)
    REFERENCES ref.organisation_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_organisation_organisation_name_not_blank CHECK (btrim(organisation_name) <> '')
);
COMMENT ON TABLE  org.organisation IS '[soft-delete] Employer, client, consultancy or campus. Stub in Phase 1; extended by Organisation and account in M7-M10';
COMMENT ON COLUMN org.organisation.organisation_name IS '[Public] Display (trading) name, max 200; legal name and identifiers added in M9';
COMMENT ON COLUMN org.organisation.organisation_status_code IS '[Internal] Account status; default pending_verification';
