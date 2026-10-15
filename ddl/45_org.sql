-- Organisation and account (schema org). Owner B. Phase 2: M7-M10 (B25, B28, B31, B34).
-- Entities and relationships: docs/phase2/org_entities.md, org_relationships.md.
-- Extends the org.organisation stub (ddl/15_stubs.sql) with ALTER TABLE; no Phase 1 FK changes.
-- Tax and registration identifiers are Sensitive: stored pgcrypto-encrypted with a key supplied per session
-- (SET app.encryption_key, held outside the database), plus an HMAC hash for duplicate detection and the last 4.

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
SELECT ref.create_lookup('ref.organisation_type', 'kind of organisation');
SELECT ref.add_lookup_value('ref.organisation_type', 'employer',        'Employer',               1);
SELECT ref.add_lookup_value('ref.organisation_type', 'client',          'Client of an agency',    2);
SELECT ref.add_lookup_value('ref.organisation_type', 'staffing_agency', 'Staffing agency',        3);
SELECT ref.add_lookup_value('ref.organisation_type', 'consultancy',     'Recruitment consultancy', 4);
SELECT ref.add_lookup_value('ref.organisation_type', 'campus',          'Campus / institution',   5);

SELECT ref.create_lookup('ref.employee_count_band', 'company size band');
SELECT ref.add_lookup_value('ref.employee_count_band', 'size_1_10',       '1-10',         1);
SELECT ref.add_lookup_value('ref.employee_count_band', 'size_11_50',      '11-50',        2);
SELECT ref.add_lookup_value('ref.employee_count_band', 'size_51_200',     '51-200',       3);
SELECT ref.add_lookup_value('ref.employee_count_band', 'size_201_1000',   '201-1,000',    4);
SELECT ref.add_lookup_value('ref.employee_count_band', 'size_1001_10000', '1,001-10,000', 5);
SELECT ref.add_lookup_value('ref.employee_count_band', 'size_10001_plus', '10,001+',      6);

SELECT ref.create_lookup('ref.account_status', 'commercial account status');
SELECT ref.add_lookup_value('ref.account_status', 'trial',     'Trial',     1);
SELECT ref.add_lookup_value('ref.account_status', 'active',    'Active',    2);
SELECT ref.add_lookup_value('ref.account_status', 'suspended', 'Suspended', 3);
SELECT ref.add_lookup_value('ref.account_status', 'closed',    'Closed',    4);

SELECT ref.create_lookup('ref.verification_kind', 'what an organisation verification checks');
SELECT ref.add_lookup_value('ref.verification_kind', 'company_registration', 'Company registration', 1);
SELECT ref.add_lookup_value('ref.verification_kind', 'tax_registration',     'Tax registration',     2);
SELECT ref.add_lookup_value('ref.verification_kind', 'address',              'Address',              3);

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE org.account (
  id                   bigint GENERATED ALWAYS AS IDENTITY,
  account_name         varchar(200) NOT NULL,
  account_status_code  d_code       NOT NULL DEFAULT 'trial',
  billing_email        d_email,
  created_at           timestamptz  NOT NULL DEFAULT now(),
  created_by           bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at           timestamptz  NOT NULL DEFAULT now(),
  updated_by           bigint       NOT NULL DEFAULT public.current_actor_id(),
  deleted_at           timestamptz,
  CONSTRAINT pk_account PRIMARY KEY (id),
  CONSTRAINT fk_account_account_status_code FOREIGN KEY (account_status_code) REFERENCES ref.account_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_account_account_name_not_blank CHECK (btrim(account_name) <> '')
);
COMMENT ON TABLE  org.account IS '[soft-delete] Commercial account (customer) that owns one or more organisations, their subscriptions and wallet';
COMMENT ON COLUMN org.account.account_name IS '[Internal] Account name, max 200';
COMMENT ON COLUMN org.account.account_status_code IS '[Internal] trial, active, suspended, closed; default trial';
COMMENT ON COLUMN org.account.billing_email IS '[Personal] Invoice recipient; null: invoices go to the primary account administrator';

-- organisation: extend the stub
ALTER TABLE org.organisation
  ADD COLUMN legal_name                varchar(250),
  ADD COLUMN organisation_type_code    d_code NOT NULL DEFAULT 'employer',
  ADD COLUMN account_id                bigint,
  ADD COLUMN parent_organisation_id    bigint,
  ADD COLUMN industry_id               bigint,
  ADD COLUMN employee_count_band_code  d_code,
  ADD COLUMN website_url               varchar(300),
  ADD COLUMN verification_status_code  d_code NOT NULL DEFAULT 'pending',
  ADD CONSTRAINT fk_organisation_organisation_type_code FOREIGN KEY (organisation_type_code) REFERENCES ref.organisation_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT fk_organisation_account_id FOREIGN KEY (account_id) REFERENCES org.account (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT fk_organisation_parent_organisation_id FOREIGN KEY (parent_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT fk_organisation_industry_id FOREIGN KEY (industry_id) REFERENCES ref.industry (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT fk_organisation_employee_count_band_code FOREIGN KEY (employee_count_band_code) REFERENCES ref.employee_count_band (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT fk_organisation_verification_status_code FOREIGN KEY (verification_status_code) REFERENCES ref.verification_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT ck_organisation_not_own_parent CHECK (parent_organisation_id <> id),
  ADD CONSTRAINT ck_organisation_website_url_format CHECK (website_url ~* '^https?://');
CREATE INDEX idx_organisation_parent_organisation_id ON org.organisation (parent_organisation_id) WHERE parent_organisation_id IS NOT NULL;
CREATE INDEX idx_organisation_account_id ON org.organisation (account_id) WHERE account_id IS NOT NULL;
CREATE INDEX idx_organisation_organisation_name_trgm ON org.organisation USING gin (organisation_name gin_trgm_ops);
COMMENT ON COLUMN org.organisation.legal_name IS '[Public] Registered legal name, max 250; null: not yet captured (verification pending) or same as organisation_name for clients';
COMMENT ON COLUMN org.organisation.organisation_type_code IS '[Public] employer, client, staffing_agency, consultancy, campus; default employer';
COMMENT ON COLUMN org.organisation.account_id IS '[Internal] Commercial account; null: not a paying customer (a client of an agency, or a past employer named on profiles)';
COMMENT ON COLUMN org.organisation.parent_organisation_id IS '[Public] Parent in the organisation hierarchy (group > subsidiary > division); null: top of its hierarchy';
COMMENT ON COLUMN org.organisation.industry_id IS '[Public] Primary industry; null: not provided';
COMMENT ON COLUMN org.organisation.employee_count_band_code IS '[Public] Company size band; null: not provided';
COMMENT ON COLUMN org.organisation.website_url IS '[Public] Company website, max 300; null: none provided';
COMMENT ON COLUMN org.organisation.verification_status_code IS '[Internal] Overall verification outcome (company and tax registration); default pending';

-- Hierarchy cycle guard: walking up from the new parent must never reach this organisation.
CREATE FUNCTION org.check_organisation_hierarchy() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  -- a direct self-reference is left to ck_organisation_not_own_parent so it fails with that name
  IF NEW.parent_organisation_id IS NOT NULL AND NEW.parent_organisation_id <> NEW.id AND EXISTS (
       WITH RECURSIVE ancestor(id, depth) AS (
         SELECT NEW.parent_organisation_id, 1
         UNION ALL
         SELECT o.parent_organisation_id, a.depth + 1
           FROM org.organisation o JOIN ancestor a ON o.id = a.id
          WHERE o.parent_organisation_id IS NOT NULL AND a.depth < 100)
       SELECT 1 FROM ancestor WHERE id = NEW.id) THEN
    RAISE EXCEPTION 'trg_organisation_hierarchy: organisation % cannot be placed under %, it would create a cycle',
                    NEW.id, NEW.parent_organisation_id USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_organisation_hierarchy BEFORE INSERT OR UPDATE OF parent_organisation_id ON org.organisation
  FOR EACH ROW EXECUTE FUNCTION org.check_organisation_hierarchy();

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE org.organisation_location (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  organisation_id  bigint       NOT NULL,
  location_name    varchar(150) NOT NULL,
  address_line1    varchar(200) NOT NULL,
  address_line2    varchar(200),
  city_id          bigint       NOT NULL,
  postal_code      varchar(12),
  latitude         d_lat,
  longitude        d_lng,
  is_headquarters  boolean      NOT NULL DEFAULT false,
  created_at       timestamptz  NOT NULL DEFAULT now(),
  created_by       bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at       timestamptz  NOT NULL DEFAULT now(),
  updated_by       bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_organisation_location PRIMARY KEY (id),
  CONSTRAINT fk_organisation_location_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_organisation_location_city_id FOREIGN KEY (city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT uq_organisation_location_organisation_id_location_name UNIQUE (organisation_id, location_name),
  CONSTRAINT ck_organisation_location_coordinates_pair CHECK ((latitude IS NULL) = (longitude IS NULL))
);
CREATE UNIQUE INDEX uq_organisation_location_one_headquarters ON org.organisation_location (organisation_id) WHERE is_headquarters;
CREATE INDEX idx_organisation_location_city_id ON org.organisation_location (city_id);
COMMENT ON TABLE  org.organisation_location IS '[hard-delete] Office or site of an organisation (owned by the organisation)';
COMMENT ON COLUMN org.organisation_location.organisation_id IS '[Internal] Owning organisation';
COMMENT ON COLUMN org.organisation_location.location_name IS '[Public] Site name (Chennai HQ), max 150';
COMMENT ON COLUMN org.organisation_location.address_line1 IS '[Public] First address line, max 200';
COMMENT ON COLUMN org.organisation_location.address_line2 IS '[Public] Second address line; null: address fits on one line';
COMMENT ON COLUMN org.organisation_location.city_id IS '[Public] City (implies state and country)';
COMMENT ON COLUMN org.organisation_location.postal_code IS '[Public] Postal or PIN code as text; nofk: free text, no postal master list; null: country without postal codes';
COMMENT ON COLUMN org.organisation_location.latitude IS '[Public] WGS84, 6 dp, source: mapping service geocode; null: not geocoded (optional boundary)';
COMMENT ON COLUMN org.organisation_location.longitude IS '[Public] WGS84, 6 dp, source: mapping service geocode; null: not geocoded (optional boundary)';
COMMENT ON COLUMN org.organisation_location.is_headquarters IS '[Public] Registered head office (at most one); default false';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE org.organisation_identifier (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  organisation_id           bigint      NOT NULL,
  identifier_type_code      d_code      NOT NULL,
  value_encrypted           bytea       NOT NULL,
  value_hash                bytea       NOT NULL,
  value_last4               varchar(4)  NOT NULL,
  verification_status_code  d_code      NOT NULL DEFAULT 'pending',
  verified_at               timestamptz,
  created_at                timestamptz NOT NULL DEFAULT now(),
  created_by                bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  updated_by                bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_organisation_identifier PRIMARY KEY (id),
  CONSTRAINT fk_organisation_identifier_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_organisation_identifier_identifier_type_code FOREIGN KEY (identifier_type_code) REFERENCES ref.identifier_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_organisation_identifier_verification_status_code FOREIGN KEY (verification_status_code) REFERENCES ref.verification_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT uq_organisation_identifier_value_hash UNIQUE (identifier_type_code, value_hash),
  CONSTRAINT uq_organisation_identifier_organisation_id_type UNIQUE (organisation_id, identifier_type_code),
  CONSTRAINT ck_organisation_identifier_hash_length CHECK (octet_length(value_hash) = 32),
  CONSTRAINT ck_organisation_identifier_last4_format CHECK (value_last4 ~ '^[A-Z0-9-]{4}$'),
  CONSTRAINT ck_organisation_identifier_verified CHECK (verification_status_code <> 'verified' OR verified_at IS NOT NULL)
);
COMMENT ON TABLE  org.organisation_identifier IS '[hard-delete] Tax or registration identifier (GSTIN, PAN, CIN, EIN) of an organisation; written through org.add_identifier, never in clear';
COMMENT ON COLUMN org.organisation_identifier.organisation_id IS '[Internal] Owning organisation';
COMMENT ON COLUMN org.organisation_identifier.identifier_type_code IS '[Internal] Identifier type; its regex and applies_to_organisation are enforced by org.add_identifier';
COMMENT ON COLUMN org.organisation_identifier.value_encrypted IS '[Sensitive] pgp_sym_encrypt of the normalised value; key supplied per session, held outside the database';
COMMENT ON COLUMN org.organisation_identifier.value_hash IS '[Sensitive] HMAC-SHA256 of the normalised value; unique per type, so the same GSTIN cannot be registered twice';
COMMENT ON COLUMN org.organisation_identifier.value_last4 IS '[Sensitive] Last 4 characters for masked display';
COMMENT ON COLUMN org.organisation_identifier.verification_status_code IS '[Internal] Outcome of the tax/registration lookup; default pending';
COMMENT ON COLUMN org.organisation_identifier.verified_at IS '[Internal] When the lookup confirmed it; null: not verified yet';

-- The only write path for identifiers: validates the format against ref.identifier_type, then stores
-- encrypted value + HMAC hash + last 4. The raw value never reaches a table or the audit trail.
CREATE FUNCTION org.add_identifier(p_organisation_id bigint, p_identifier_type_code text, p_raw_value text)
RETURNS bigint
LANGUAGE plpgsql AS
$$
DECLARE
  v_type  ref.identifier_type;
  v_value text := upper(regexp_replace(coalesce(p_raw_value, ''), '\s', '', 'g'));
  v_key   text := current_setting('app.encryption_key', true);
  v_id    bigint;
BEGIN
  SELECT * INTO v_type FROM ref.identifier_type WHERE code = p_identifier_type_code AND is_active;
  IF NOT FOUND OR NOT v_type.applies_to_organisation THEN
    RAISE EXCEPTION 'org.add_identifier: % is not an organisation identifier type', p_identifier_type_code
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_type.validation_regex IS NOT NULL AND v_value !~ v_type.validation_regex THEN
    RAISE EXCEPTION 'org.add_identifier: value does not match the % format', p_identifier_type_code
      USING ERRCODE = 'check_violation';
  END IF;
  IF coalesce(v_key, '') = '' THEN
    RAISE EXCEPTION 'org.add_identifier: app.encryption_key is not set for this session' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO org.organisation_identifier (organisation_id, identifier_type_code, value_encrypted, value_hash, value_last4)
  VALUES (p_organisation_id, p_identifier_type_code, pgp_sym_encrypt(v_value, v_key),
          hmac(v_value, v_key, 'sha256'), right(v_value, 4))
  RETURNING id INTO v_id;
  RETURN v_id;
END
$$;

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE org.verification (
  id                          bigint GENERATED ALWAYS AS IDENTITY,
  organisation_id             bigint       NOT NULL,
  verification_kind_code      d_code       NOT NULL,
  organisation_identifier_id  bigint,
  verification_status_code    d_code       NOT NULL DEFAULT 'pending',
  idempotency_key             varchar(64)  NOT NULL,
  provider_reference          varchar(100),
  requested_at                timestamptz  NOT NULL DEFAULT now(),
  completed_at                timestamptz,
  outcome_note                varchar(500),
  created_at                  timestamptz  NOT NULL DEFAULT now(),
  created_by                  bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                  timestamptz  NOT NULL DEFAULT now(),
  updated_by                  bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_verification PRIMARY KEY (id),
  CONSTRAINT fk_verification_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_verification_verification_kind_code FOREIGN KEY (verification_kind_code) REFERENCES ref.verification_kind (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_verification_organisation_identifier_id FOREIGN KEY (organisation_identifier_id) REFERENCES org.organisation_identifier (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_verification_verification_status_code FOREIGN KEY (verification_status_code) REFERENCES ref.verification_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT uq_verification_idempotency_key UNIQUE (idempotency_key),
  CONSTRAINT uq_verification_provider_reference UNIQUE (provider_reference),
  CONSTRAINT ck_verification_completed CHECK ((verification_status_code = 'pending') = (completed_at IS NULL)),
  CONSTRAINT ck_verification_time_range CHECK (completed_at IS NULL OR completed_at >= requested_at)
);
CREATE INDEX idx_verification_organisation_id ON org.verification (organisation_id, requested_at);
CREATE INDEX idx_verification_organisation_identifier_id ON org.verification (organisation_identifier_id) WHERE organisation_identifier_id IS NOT NULL;
COMMENT ON TABLE  org.verification IS '[hard-delete] One verification request to the company registration / tax service and its outcome (integration boundary, docket Section 6)';
COMMENT ON COLUMN org.verification.organisation_id IS '[Internal] Organisation being verified';
COMMENT ON COLUMN org.verification.verification_kind_code IS '[Internal] company_registration, tax_registration, address';
COMMENT ON COLUMN org.verification.organisation_identifier_id IS '[Internal] Identifier used for the lookup; null: address verification needs no identifier';
COMMENT ON COLUMN org.verification.verification_status_code IS '[Internal] pending until the provider answers; default pending';
COMMENT ON COLUMN org.verification.idempotency_key IS '[Internal] Key sent to the provider so a retried request is not processed twice';
COMMENT ON COLUMN org.verification.provider_reference IS '[Internal] Provider request id (unique); null: provider has not acknowledged yet (retry pending)';
COMMENT ON COLUMN org.verification.requested_at IS '[Internal] When the request was sent (UTC)';
COMMENT ON COLUMN org.verification.completed_at IS '[Internal] When the provider answered (UTC); null: still pending';
COMMENT ON COLUMN org.verification.outcome_note IS '[Internal] Provider remark, max 500; null: none';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE org.account_administrator (
  id           bigint GENERATED ALWAYS AS IDENTITY,
  account_id   bigint      NOT NULL,
  app_user_id  bigint      NOT NULL,
  is_primary   boolean     NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_account_administrator PRIMARY KEY (id),
  CONSTRAINT fk_account_administrator_account_id FOREIGN KEY (account_id) REFERENCES org.account (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_account_administrator_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT uq_account_administrator_account_id_app_user_id UNIQUE (account_id, app_user_id)
);
CREATE UNIQUE INDEX uq_account_administrator_one_primary ON org.account_administrator (account_id) WHERE is_primary;
CREATE INDEX idx_account_administrator_app_user_id ON org.account_administrator (app_user_id);
COMMENT ON TABLE  org.account_administrator IS '[hard-delete] User who administers a commercial account (owned by the account); at most one primary';
COMMENT ON COLUMN org.account_administrator.account_id IS '[Internal] Account administered';
COMMENT ON COLUMN org.account_administrator.app_user_id IS '[Internal] Administrator';
COMMENT ON COLUMN org.account_administrator.is_primary IS '[Internal] Primary contact for billing and notices (at most one); default false';

-- ---------------------------------------------------------------------------------------------------
-- Recruiter mapping (B34): effective-dated, a recruiter belongs to one organisation at a time.
CREATE TABLE org.recruiter_mapping (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id      bigint      NOT NULL,
  organisation_id  bigint      NOT NULL,
  valid_period     daterange   NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_recruiter_mapping PRIMARY KEY (id),
  CONSTRAINT fk_recruiter_mapping_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_recruiter_mapping_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_recruiter_mapping_valid_period CHECK (NOT isempty(valid_period) AND lower(valid_period) IS NOT NULL),
  CONSTRAINT ex_recruiter_mapping_valid_range EXCLUDE USING gist (app_user_id WITH =, valid_period WITH &&)
);
CREATE INDEX idx_recruiter_mapping_organisation_id ON org.recruiter_mapping (organisation_id);
COMMENT ON TABLE  org.recruiter_mapping IS '[hard-delete] Which organisation a recruiter works for, over which dates; periods for one recruiter never overlap (history kept by closing the period)';
COMMENT ON COLUMN org.recruiter_mapping.app_user_id IS '[Internal] Recruiter';
COMMENT ON COLUMN org.recruiter_mapping.organisation_id IS '[Internal] Organisation the recruiter acts for (RLS key in M18)';
COMMENT ON COLUMN org.recruiter_mapping.valid_period IS '[Internal] Dates [from, to) the mapping is effective; open upper bound = current';

-- Current organisation of a recruiter (used by RLS in M18 and by the job posting checks)
CREATE FUNCTION org.current_recruiter_organisation(p_app_user_id bigint) RETURNS bigint
LANGUAGE sql STABLE AS
$$
  SELECT organisation_id FROM org.recruiter_mapping
   WHERE app_user_id = p_app_user_id AND valid_period @> current_date
$$;
GRANT EXECUTE ON FUNCTION org.current_recruiter_organisation(bigint) TO talentra_app, talentra_readonly;
