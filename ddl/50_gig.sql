-- Gig marketplace (schema gig). Owner C. Phase 2: M7-M10 (B26, B29, B32, B35).
-- Entities and relationships: docs/phase2/gig_entities.md, gig_relationships.md.
-- Separate subsystem (decision in 00_decisions.md section 8): shares identity, master data and analytics dimensions.
-- Rules from docket Section 2:
--   * workers apply to requests; only the requester accepts or rejects (trg_gig_application_decision)
--   * blacklisted workers cannot apply to that requester's gigs (trg_gig_application_blacklist)
--   * a worker's active / handed-off assignment windows never overlap (ex_gig_assignment_worker_window, B35)
--   * fulfilment is external: handoff reference + idempotency key; earnings come only from the integration role
--   * requesters rate completed gigs, once (trg_gig_rating_completed_assignment)
-- Windows are two timestamptz columns with a CHECK (so a reversed window fails with a named constraint);
-- the exclusion constraint builds tstzrange(window_start, window_end) from them.

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
SELECT ref.create_lookup('ref.pricing_model', 'how a gig is priced');
SELECT ref.add_lookup_value('ref.pricing_model', 'fixed', 'Fixed price', 1);
SELECT ref.add_lookup_value('ref.pricing_model', 'rate',  'Rate based',  2);

SELECT ref.create_lookup('ref.rate_unit', 'unit a gig rate is charged per');
SELECT ref.add_lookup_value('ref.rate_unit', 'hour', 'Per hour', 1);
SELECT ref.add_lookup_value('ref.rate_unit', 'day',  'Per day',  2);
SELECT ref.add_lookup_value('ref.rate_unit', 'task', 'Per task', 3);

SELECT ref.create_lookup('ref.gig_request_status', 'gig request lifecycle');
SELECT ref.add_lookup_value('ref.gig_request_status', 'draft',     'Draft',     1);
SELECT ref.add_lookup_value('ref.gig_request_status', 'open',      'Open',      2);
SELECT ref.add_lookup_value('ref.gig_request_status', 'assigned',  'Assigned',  3);
SELECT ref.add_lookup_value('ref.gig_request_status', 'completed', 'Completed', 4);
SELECT ref.add_lookup_value('ref.gig_request_status', 'cancelled', 'Cancelled', 5);

SELECT ref.create_lookup('ref.gig_application_status', 'state of a gig application');
SELECT ref.add_lookup_value('ref.gig_application_status', 'applied',   'Applied',   1);
SELECT ref.add_lookup_value('ref.gig_application_status', 'accepted',  'Accepted',  2);
SELECT ref.add_lookup_value('ref.gig_application_status', 'rejected',  'Rejected',  3);
SELECT ref.add_lookup_value('ref.gig_application_status', 'withdrawn', 'Withdrawn', 4);

SELECT ref.create_lookup('ref.gig_assignment_status', 'state of a gig assignment');
SELECT ref.add_lookup_value('ref.gig_assignment_status', 'active',     'Active',     1);
SELECT ref.add_lookup_value('ref.gig_assignment_status', 'handed_off', 'Handed off to fulfilment', 2);
SELECT ref.add_lookup_value('ref.gig_assignment_status', 'completed',  'Completed',  3);
SELECT ref.add_lookup_value('ref.gig_assignment_status', 'cancelled',  'Cancelled',  4);

SELECT ref.create_lookup('ref.handoff_status', 'state of a handoff to the external fulfilment system');
SELECT ref.add_lookup_value('ref.handoff_status', 'pending',      'Pending',      1);
SELECT ref.add_lookup_value('ref.handoff_status', 'sent',         'Sent',         2);
SELECT ref.add_lookup_value('ref.handoff_status', 'acknowledged', 'Acknowledged', 3);
SELECT ref.add_lookup_value('ref.handoff_status', 'failed',       'Failed',       4);

SELECT ref.create_lookup('ref.earning_kind', 'kind of earnings figure reported by the fulfilment system');
SELECT ref.add_lookup_value('ref.earning_kind', 'estimated', 'Estimated', 1);
SELECT ref.add_lookup_value('ref.earning_kind', 'projected', 'Projected', 2);
SELECT ref.add_lookup_value('ref.earning_kind', 'total',     'Total',     3);

SELECT ref.create_lookup('ref.worker_list_kind', 'requester list a gig worker is on');
SELECT ref.add_lookup_value('ref.worker_list_kind', 'favourite', 'Favourite', 1);
SELECT ref.add_lookup_value('ref.worker_list_kind', 'blacklist', 'Blacklist', 2);

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE gig.gig_worker_profile (
  id                bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id       bigint        NOT NULL,
  headline          varchar(250)  NOT NULL,
  bio               varchar(2000),
  bio_language_id   bigint,
  base_city_id      bigint,
  is_available      boolean       NOT NULL DEFAULT true,
  created_at        timestamptz   NOT NULL DEFAULT now(),
  created_by        bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at        timestamptz   NOT NULL DEFAULT now(),
  updated_by        bigint        NOT NULL DEFAULT public.current_actor_id(),
  deleted_at        timestamptz,
  CONSTRAINT pk_gig_worker_profile PRIMARY KEY (id),
  CONSTRAINT uq_gig_worker_profile_app_user_id UNIQUE (app_user_id),
  CONSTRAINT fk_gig_worker_profile_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_worker_profile_bio_language_id FOREIGN KEY (bio_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_worker_profile_base_city_id FOREIGN KEY (base_city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_gig_worker_profile_bio_language CHECK (bio_language_id IS NULL OR bio IS NOT NULL)
);
COMMENT ON TABLE  gig.gig_worker_profile IS '[soft-delete] Gig worker profile, separate from candidate profiles (docket Section 2); 1:1 with app_user';
COMMENT ON COLUMN gig.gig_worker_profile.app_user_id IS '[Internal] Login identity (unique)';
COMMENT ON COLUMN gig.gig_worker_profile.headline IS '[Personal] One-line pitch, max 250';
COMMENT ON COLUMN gig.gig_worker_profile.bio IS '[Personal] About the worker, max 2000; null: not written';
COMMENT ON COLUMN gig.gig_worker_profile.bio_language_id IS '[Internal] Language of bio; null: no bio or not detected (RG7)';
COMMENT ON COLUMN gig.gig_worker_profile.base_city_id IS '[Personal] City the worker is based in; null: remote-only worker';
COMMENT ON COLUMN gig.gig_worker_profile.is_available IS '[Personal] Accepting new gigs (calendar detail in gig_availability); default true';

CREATE TABLE gig.gig_service_offering (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  gig_worker_profile_id  bigint        NOT NULL,
  skill_id               bigint        NOT NULL,
  offering_title         varchar(150)  NOT NULL,
  offering_description   varchar(1000),
  created_at             timestamptz   NOT NULL DEFAULT now(),
  created_by             bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz   NOT NULL DEFAULT now(),
  updated_by             bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_service_offering PRIMARY KEY (id),
  CONSTRAINT uq_gig_service_offering_gig_worker_profile_id_skill_id UNIQUE (gig_worker_profile_id, skill_id),
  CONSTRAINT fk_gig_service_offering_gig_worker_profile_id FOREIGN KEY (gig_worker_profile_id) REFERENCES gig.gig_worker_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_gig_service_offering_skill_id FOREIGN KEY (skill_id) REFERENCES ref.skill (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_gig_service_offering_skill_id ON gig.gig_service_offering (skill_id);
COMMENT ON TABLE  gig.gig_service_offering IS '[hard-delete] Service a gig worker offers, one per skill (owned by the worker profile)';
COMMENT ON COLUMN gig.gig_service_offering.gig_worker_profile_id IS '[Internal] Owning worker';
COMMENT ON COLUMN gig.gig_service_offering.skill_id IS '[Public] Skill offered';
COMMENT ON COLUMN gig.gig_service_offering.offering_title IS '[Public] Title, max 150';
COMMENT ON COLUMN gig.gig_service_offering.offering_description IS '[Public] Description, max 1000; null: title is self-explanatory';

CREATE TABLE gig.gig_charge_rate (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  gig_service_offering_id  bigint          NOT NULL,
  rate_unit_code           d_code          NOT NULL,
  rate_amount              d_money         NOT NULL,
  rate_currency_code       d_currency_code NOT NULL,
  valid_period             daterange       NOT NULL,
  created_at               timestamptz     NOT NULL DEFAULT now(),
  created_by               bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz     NOT NULL DEFAULT now(),
  updated_by               bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_charge_rate PRIMARY KEY (id),
  CONSTRAINT fk_gig_charge_rate_gig_service_offering_id FOREIGN KEY (gig_service_offering_id) REFERENCES gig.gig_service_offering (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_gig_charge_rate_rate_unit_code FOREIGN KEY (rate_unit_code) REFERENCES ref.rate_unit (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_charge_rate_rate_currency_code FOREIGN KEY (rate_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_gig_charge_rate_rate_amount CHECK (rate_amount > 0),
  CONSTRAINT ck_gig_charge_rate_valid_period CHECK (NOT isempty(valid_period) AND lower(valid_period) IS NOT NULL),
  CONSTRAINT ex_gig_charge_rate_no_overlap EXCLUDE USING gist (gig_service_offering_id WITH =, rate_unit_code WITH =, valid_period WITH &&)
);
COMMENT ON TABLE  gig.gig_charge_rate IS '[hard-delete] Effective-dated charge rate of a service offering; one rate per unit at a time (owned by the offering)';
COMMENT ON COLUMN gig.gig_charge_rate.gig_service_offering_id IS '[Internal] Owning offering';
COMMENT ON COLUMN gig.gig_charge_rate.rate_unit_code IS '[Public] hour, day, task';
COMMENT ON COLUMN gig.gig_charge_rate.rate_amount IS '[Public] Rate per unit';
COMMENT ON COLUMN gig.gig_charge_rate.rate_currency_code IS '[Public] Currency of rate_amount';
COMMENT ON COLUMN gig.gig_charge_rate.valid_period IS '[Public] Dates [from, to) the rate applies; open upper bound = current';

CREATE TABLE gig.gig_availability (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  gig_worker_profile_id  bigint      NOT NULL,
  available_from         timestamptz NOT NULL,
  available_to           timestamptz NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  created_by             bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_availability PRIMARY KEY (id),
  CONSTRAINT fk_gig_availability_gig_worker_profile_id FOREIGN KEY (gig_worker_profile_id) REFERENCES gig.gig_worker_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT ck_gig_availability_time_range CHECK (available_to > available_from),
  CONSTRAINT ex_gig_availability_no_overlap EXCLUDE USING gist (gig_worker_profile_id WITH =, tstzrange(available_from, available_to) WITH &&)
);
COMMENT ON TABLE  gig.gig_availability IS '[hard-delete] Time slot a gig worker is available; slots of one worker do not overlap (owned by the worker profile)';
COMMENT ON COLUMN gig.gig_availability.gig_worker_profile_id IS '[Internal] Owning worker';
COMMENT ON COLUMN gig.gig_availability.available_from IS '[Personal] Slot start (UTC)';
COMMENT ON COLUMN gig.gig_availability.available_to IS '[Personal] Slot end (UTC), after the start';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE gig.gig_request (
  id                          bigint GENERATED ALWAYS AS IDENTITY,
  requester_app_user_id       bigint          NOT NULL,
  requester_organisation_id   bigint,
  gig_title                   varchar(200)    NOT NULL,
  gig_description             varchar(4000)   NOT NULL,
  gig_description_language_id bigint,
  skill_id                    bigint          NOT NULL,
  city_id                     bigint,
  window_start                timestamptz     NOT NULL,
  window_end                  timestamptz     NOT NULL,
  pricing_model_code          d_code          NOT NULL,
  fixed_price_amount          d_money,
  rate_amount                 d_money,
  rate_unit_code              d_code,
  currency_code               d_currency_code NOT NULL,
  gig_request_status_code     d_code          NOT NULL DEFAULT 'draft',
  created_at                  timestamptz     NOT NULL DEFAULT now(),
  created_by                  bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at                  timestamptz     NOT NULL DEFAULT now(),
  updated_by                  bigint          NOT NULL DEFAULT public.current_actor_id(),
  deleted_at                  timestamptz,
  CONSTRAINT pk_gig_request PRIMARY KEY (id),
  CONSTRAINT fk_gig_request_requester_app_user_id FOREIGN KEY (requester_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_request_requester_organisation_id FOREIGN KEY (requester_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_request_gig_description_language_id FOREIGN KEY (gig_description_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_request_skill_id FOREIGN KEY (skill_id) REFERENCES ref.skill (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_request_city_id FOREIGN KEY (city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_request_pricing_model_code FOREIGN KEY (pricing_model_code) REFERENCES ref.pricing_model (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_request_rate_unit_code FOREIGN KEY (rate_unit_code) REFERENCES ref.rate_unit (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_request_currency_code FOREIGN KEY (currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_request_gig_request_status_code FOREIGN KEY (gig_request_status_code) REFERENCES ref.gig_request_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_gig_request_window CHECK (window_end > window_start),
  CONSTRAINT ck_gig_request_pricing CHECK (
        (pricing_model_code = 'fixed' AND fixed_price_amount IS NOT NULL AND rate_amount IS NULL AND rate_unit_code IS NULL)
     OR (pricing_model_code = 'rate'  AND rate_amount IS NOT NULL AND rate_unit_code IS NOT NULL AND fixed_price_amount IS NULL)),
  CONSTRAINT ck_gig_request_amounts_positive CHECK (fixed_price_amount > 0 AND rate_amount > 0),
  CONSTRAINT ck_gig_request_description_language CHECK (gig_description_language_id IS NULL OR gig_description IS NOT NULL)
);
CREATE INDEX idx_gig_request_open ON gig.gig_request (skill_id, window_start)
  WHERE gig_request_status_code = 'open' AND deleted_at IS NULL;
CREATE INDEX idx_gig_request_requester_app_user_id ON gig.gig_request (requester_app_user_id);
CREATE INDEX idx_gig_request_requester_organisation_id ON gig.gig_request (requester_organisation_id) WHERE requester_organisation_id IS NOT NULL;
COMMENT ON TABLE  gig.gig_request IS '[soft-delete] Short project-based request with a time window and a fixed or rate-based price';
COMMENT ON COLUMN gig.gig_request.requester_app_user_id IS '[Internal] User who posted the gig and alone decides on applications';
COMMENT ON COLUMN gig.gig_request.requester_organisation_id IS '[Internal] Organisation the requester posts for; null: individual requester';
COMMENT ON COLUMN gig.gig_request.gig_title IS '[Public] Title, max 200';
COMMENT ON COLUMN gig.gig_request.gig_description IS '[Public] Scope of work, max 4000';
COMMENT ON COLUMN gig.gig_request.gig_description_language_id IS '[Public] Language of the description; null: not detected (RG7)';
COMMENT ON COLUMN gig.gig_request.skill_id IS '[Public] Primary skill required';
COMMENT ON COLUMN gig.gig_request.city_id IS '[Public] Where the work happens; null: remote gig';
COMMENT ON COLUMN gig.gig_request.window_start IS '[Public] Work window start (UTC)';
COMMENT ON COLUMN gig.gig_request.window_end IS '[Public] Work window end (UTC), after the start';
COMMENT ON COLUMN gig.gig_request.pricing_model_code IS '[Public] fixed or rate';
COMMENT ON COLUMN gig.gig_request.fixed_price_amount IS '[Public] Total price; null: rate-based gig (CHECK)';
COMMENT ON COLUMN gig.gig_request.rate_amount IS '[Public] Price per rate unit; null: fixed-price gig (CHECK)';
COMMENT ON COLUMN gig.gig_request.rate_unit_code IS '[Public] Unit of rate_amount; null: fixed-price gig (CHECK)';
COMMENT ON COLUMN gig.gig_request.currency_code IS '[Public] Currency of the price';
COMMENT ON COLUMN gig.gig_request.gig_request_status_code IS '[Internal] Lifecycle; default draft';

CREATE TABLE gig.gig_application (
  id                           bigint GENERATED ALWAYS AS IDENTITY,
  gig_request_id               bigint          NOT NULL,
  gig_worker_profile_id        bigint          NOT NULL,
  gig_application_status_code  d_code          NOT NULL DEFAULT 'applied',
  proposed_amount              d_money,
  proposed_currency_code       d_currency_code,
  cover_note                   varchar(1000),
  applied_at                   timestamptz     NOT NULL DEFAULT now(),
  decided_at                   timestamptz,
  created_at                   timestamptz     NOT NULL DEFAULT now(),
  created_by                   bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at                   timestamptz     NOT NULL DEFAULT now(),
  updated_by                   bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_application PRIMARY KEY (id),
  CONSTRAINT uq_gig_application_gig_request_id_gig_worker_profile_id UNIQUE (gig_request_id, gig_worker_profile_id),
  CONSTRAINT uq_gig_application_id_request_worker UNIQUE (id, gig_request_id, gig_worker_profile_id),
  CONSTRAINT fk_gig_application_gig_request_id FOREIGN KEY (gig_request_id) REFERENCES gig.gig_request (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_application_gig_worker_profile_id FOREIGN KEY (gig_worker_profile_id) REFERENCES gig.gig_worker_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_application_gig_application_status_code FOREIGN KEY (gig_application_status_code) REFERENCES ref.gig_application_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_application_proposed_currency_code FOREIGN KEY (proposed_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_gig_application_proposal CHECK ((proposed_amount IS NULL) = (proposed_currency_code IS NULL) AND proposed_amount > 0),
  CONSTRAINT ck_gig_application_decided CHECK ((gig_application_status_code IN ('accepted', 'rejected')) = (decided_at IS NOT NULL))
);
CREATE INDEX idx_gig_application_gig_worker_profile_id ON gig.gig_application (gig_worker_profile_id);
COMMENT ON TABLE  gig.gig_application IS '[hard-delete] Gig worker applies to a gig request; bids flow one way and only the requester decides';
COMMENT ON COLUMN gig.gig_application.gig_request_id IS '[Internal] Gig applied to';
COMMENT ON COLUMN gig.gig_application.gig_worker_profile_id IS '[Internal] Applying worker';
COMMENT ON COLUMN gig.gig_application.gig_application_status_code IS '[Internal] applied, accepted, rejected, withdrawn; default applied';
COMMENT ON COLUMN gig.gig_application.proposed_amount IS '[Personal] Counter-price; null: worker accepts the posted price';
COMMENT ON COLUMN gig.gig_application.proposed_currency_code IS '[Personal] Currency of proposed_amount; null: no counter-price';
COMMENT ON COLUMN gig.gig_application.cover_note IS '[Personal] Note to the requester, max 1000; null: none';
COMMENT ON COLUMN gig.gig_application.applied_at IS '[Internal] Application instant (UTC)';
COMMENT ON COLUMN gig.gig_application.decided_at IS '[Internal] When the requester accepted or rejected; null: not decided yet (or withdrawn by the worker)';

CREATE TABLE gig.gig_assignment (
  id                          bigint GENERATED ALWAYS AS IDENTITY,
  gig_application_id          bigint      NOT NULL,
  gig_request_id              bigint      NOT NULL,
  gig_worker_profile_id       bigint      NOT NULL,
  window_start                timestamptz NOT NULL,
  window_end                  timestamptz NOT NULL,
  gig_assignment_status_code  d_code      NOT NULL DEFAULT 'active',
  completed_at                timestamptz,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  created_by                  bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  updated_by                  bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_assignment PRIMARY KEY (id),
  CONSTRAINT uq_gig_assignment_gig_application_id UNIQUE (gig_application_id),
  -- the assignment's request and worker must be those of its application
  CONSTRAINT fk_gig_assignment_application FOREIGN KEY (gig_application_id, gig_request_id, gig_worker_profile_id)
    REFERENCES gig.gig_application (id, gig_request_id, gig_worker_profile_id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_assignment_gig_request_id FOREIGN KEY (gig_request_id) REFERENCES gig.gig_request (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_assignment_gig_worker_profile_id FOREIGN KEY (gig_worker_profile_id) REFERENCES gig.gig_worker_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_assignment_gig_assignment_status_code FOREIGN KEY (gig_assignment_status_code) REFERENCES ref.gig_assignment_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_gig_assignment_window CHECK (window_end > window_start),
  CONSTRAINT ck_gig_assignment_completed CHECK ((gig_assignment_status_code = 'completed') = (completed_at IS NOT NULL)),
  -- B35: a worker's live assignment windows never overlap (cancelled / completed ones do not count)
  CONSTRAINT ex_gig_assignment_worker_window EXCLUDE USING gist (
    gig_worker_profile_id WITH =, tstzrange(window_start, window_end) WITH &&)
    WHERE (gig_assignment_status_code IN ('active', 'handed_off'))
);
CREATE INDEX idx_gig_assignment_gig_request_id ON gig.gig_assignment (gig_request_id);
COMMENT ON TABLE  gig.gig_assignment IS '[hard-delete] Accepted gig application turned into work for a window; fulfilment itself runs in the external system';
COMMENT ON COLUMN gig.gig_assignment.gig_application_id IS '[Internal] Accepted application (unique)';
COMMENT ON COLUMN gig.gig_assignment.gig_request_id IS '[Internal] Gig (copied from the application, checked by the composite FK)';
COMMENT ON COLUMN gig.gig_assignment.gig_worker_profile_id IS '[Internal] Worker (copied from the application for the overlap rule)';
COMMENT ON COLUMN gig.gig_assignment.window_start IS '[Internal] Agreed work window start (UTC)';
COMMENT ON COLUMN gig.gig_assignment.window_end IS '[Internal] Agreed work window end (UTC), after the start';
COMMENT ON COLUMN gig.gig_assignment.gig_assignment_status_code IS '[Internal] active, handed_off, completed, cancelled; default active';
COMMENT ON COLUMN gig.gig_assignment.completed_at IS '[Internal] Completion reconciled from the fulfilment system (UTC); null: not completed';

CREATE TABLE gig.gig_fulfilment_handoff (
  id                   bigint GENERATED ALWAYS AS IDENTITY,
  gig_assignment_id    bigint       NOT NULL,
  idempotency_key      varchar(64)  NOT NULL,
  external_reference   varchar(100),
  handoff_status_code  d_code       NOT NULL DEFAULT 'pending',
  sent_at              timestamptz,
  acknowledged_at      timestamptz,
  last_error           varchar(500),
  created_at           timestamptz  NOT NULL DEFAULT now(),
  created_by           bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at           timestamptz  NOT NULL DEFAULT now(),
  updated_by           bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_fulfilment_handoff PRIMARY KEY (id),
  CONSTRAINT uq_gig_fulfilment_handoff_gig_assignment_id UNIQUE (gig_assignment_id),
  CONSTRAINT uq_gig_fulfilment_handoff_idempotency_key UNIQUE (idempotency_key),
  CONSTRAINT uq_gig_fulfilment_handoff_external_reference UNIQUE (external_reference),
  CONSTRAINT fk_gig_fulfilment_handoff_gig_assignment_id FOREIGN KEY (gig_assignment_id) REFERENCES gig.gig_assignment (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_fulfilment_handoff_handoff_status_code FOREIGN KEY (handoff_status_code) REFERENCES ref.handoff_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_gig_fulfilment_handoff_acknowledged CHECK ((handoff_status_code = 'acknowledged') = (external_reference IS NOT NULL AND acknowledged_at IS NOT NULL)),
  CONSTRAINT ck_gig_fulfilment_handoff_sent CHECK (handoff_status_code = 'pending' OR sent_at IS NOT NULL)
);
COMMENT ON TABLE  gig.gig_fulfilment_handoff IS '[hard-delete] Handoff of an assignment to the external fulfilment system (integration boundary): idempotent send, external reference, status';
COMMENT ON COLUMN gig.gig_fulfilment_handoff.gig_assignment_id IS '[Internal] Assignment handed off (one handoff per assignment)';
COMMENT ON COLUMN gig.gig_fulfilment_handoff.idempotency_key IS '[Internal] Key sent with every retry so the fulfilment system creates the job once';
COMMENT ON COLUMN gig.gig_fulfilment_handoff.external_reference IS '[Internal] Job id in the fulfilment system (unique); null: not acknowledged yet';
COMMENT ON COLUMN gig.gig_fulfilment_handoff.handoff_status_code IS '[Internal] pending, sent, acknowledged, failed; default pending';
COMMENT ON COLUMN gig.gig_fulfilment_handoff.sent_at IS '[Internal] Last send attempt (UTC); null: not sent yet';
COMMENT ON COLUMN gig.gig_fulfilment_handoff.acknowledged_at IS '[Internal] When the fulfilment system confirmed (UTC); null: not confirmed';
COMMENT ON COLUMN gig.gig_fulfilment_handoff.last_error IS '[Internal] Last failure reason, max 500; null: no failure';

CREATE TABLE gig.gig_earning_reference (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  gig_assignment_id   bigint          NOT NULL,
  earning_kind_code   d_code          NOT NULL,
  earning_amount      d_money         NOT NULL,
  currency_code       d_currency_code NOT NULL,
  source_system       varchar(50)     NOT NULL,
  source_reference    varchar(100)    NOT NULL,
  as_of               timestamptz     NOT NULL,
  reconciled_at       timestamptz     NOT NULL DEFAULT now(),
  created_at          timestamptz     NOT NULL DEFAULT now(),
  created_by          bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_earning_reference PRIMARY KEY (id),
  CONSTRAINT uq_gig_earning_reference_source UNIQUE (source_system, source_reference),
  CONSTRAINT fk_gig_earning_reference_gig_assignment_id FOREIGN KEY (gig_assignment_id) REFERENCES gig.gig_assignment (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_earning_reference_earning_kind_code FOREIGN KEY (earning_kind_code) REFERENCES ref.earning_kind (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_earning_reference_currency_code FOREIGN KEY (currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_gig_earning_reference_amount CHECK (earning_amount >= 0)
);
CREATE INDEX idx_gig_earning_reference_gig_assignment_id ON gig.gig_earning_reference (gig_assignment_id, earning_kind_code, as_of DESC);
COMMENT ON TABLE  gig.gig_earning_reference IS '[append-only] [integration-write] Estimated, projected and total earnings reported by the fulfilment system (source of truth); a newer figure is a new row. The application can only read it';
COMMENT ON COLUMN gig.gig_earning_reference.gig_assignment_id IS '[Internal] Assignment the figure is for';
COMMENT ON COLUMN gig.gig_earning_reference.earning_kind_code IS '[Internal] estimated, projected, total';
COMMENT ON COLUMN gig.gig_earning_reference.earning_amount IS '[Personal] Amount as reported';
COMMENT ON COLUMN gig.gig_earning_reference.currency_code IS '[Personal] Currency of earning_amount';
COMMENT ON COLUMN gig.gig_earning_reference.source_system IS '[Internal] Reporting system name, max 50';
COMMENT ON COLUMN gig.gig_earning_reference.source_reference IS '[Internal] Event id in the source system; unique with source_system, so a replayed event is rejected (idempotency)';
COMMENT ON COLUMN gig.gig_earning_reference.as_of IS '[Internal] Instant the figure is valid for, per the source (UTC)';
COMMENT ON COLUMN gig.gig_earning_reference.reconciled_at IS '[Internal] When we stored it (UTC)';

CREATE TABLE gig.gig_requester_worker_list (
  id                         bigint GENERATED ALWAYS AS IDENTITY,
  requester_app_user_id      bigint       NOT NULL,
  gig_worker_profile_id      bigint       NOT NULL,
  worker_list_kind_code      d_code       NOT NULL,
  list_note                  varchar(300),
  created_at                 timestamptz  NOT NULL DEFAULT now(),
  created_by                 bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                 timestamptz  NOT NULL DEFAULT now(),
  updated_by                 bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_requester_worker_list PRIMARY KEY (id),
  CONSTRAINT uq_gig_requester_worker_list_requester_worker UNIQUE (requester_app_user_id, gig_worker_profile_id),
  CONSTRAINT fk_gig_requester_worker_list_requester_app_user_id FOREIGN KEY (requester_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_gig_requester_worker_list_gig_worker_profile_id FOREIGN KEY (gig_worker_profile_id) REFERENCES gig.gig_worker_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_gig_requester_worker_list_worker_list_kind_code FOREIGN KEY (worker_list_kind_code) REFERENCES ref.worker_list_kind (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_gig_requester_worker_list_gig_worker_profile_id ON gig.gig_requester_worker_list (gig_worker_profile_id);
COMMENT ON TABLE  gig.gig_requester_worker_list IS '[hard-delete] Requester favourite or blacklist entry for a worker; a worker is on at most one list per requester (owned by both sides)';
COMMENT ON COLUMN gig.gig_requester_worker_list.requester_app_user_id IS '[Internal] Requester maintaining the list';
COMMENT ON COLUMN gig.gig_requester_worker_list.gig_worker_profile_id IS '[Internal] Worker listed';
COMMENT ON COLUMN gig.gig_requester_worker_list.worker_list_kind_code IS '[Internal] favourite or blacklist';
COMMENT ON COLUMN gig.gig_requester_worker_list.list_note IS '[Personal] Private note, max 300; null: none';

CREATE TABLE gig.gig_rating (
  id                 bigint GENERATED ALWAYS AS IDENTITY,
  gig_assignment_id  bigint        NOT NULL,
  rating_score       smallint      NOT NULL,
  review_text        varchar(1000),
  review_language_id bigint,
  created_at         timestamptz   NOT NULL DEFAULT now(),
  created_by         bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at         timestamptz   NOT NULL DEFAULT now(),
  updated_by         bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_gig_rating PRIMARY KEY (id),
  CONSTRAINT uq_gig_rating_gig_assignment_id UNIQUE (gig_assignment_id),
  CONSTRAINT fk_gig_rating_gig_assignment_id FOREIGN KEY (gig_assignment_id) REFERENCES gig.gig_assignment (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_gig_rating_review_language_id FOREIGN KEY (review_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_gig_rating_rating_score CHECK (rating_score BETWEEN 1 AND 5),
  CONSTRAINT ck_gig_rating_review_language CHECK (review_language_id IS NULL OR review_text IS NOT NULL)
);
COMMENT ON TABLE  gig.gig_rating IS '[hard-delete] Requester rating of a completed gig, one per assignment';
COMMENT ON COLUMN gig.gig_rating.gig_assignment_id IS '[Internal] Completed assignment rated (unique)';
COMMENT ON COLUMN gig.gig_rating.rating_score IS '[Public] Score 1-5';
COMMENT ON COLUMN gig.gig_rating.review_text IS '[Public] Review, max 1000; null: score only';
COMMENT ON COLUMN gig.gig_rating.review_language_id IS '[Public] Language of review_text; null: no review or not detected';

-- ---------------------------------------------------------------------------------------------------
-- Business rules that span rows
CREATE FUNCTION gig.check_gig_application() RETURNS trigger
LANGUAGE plpgsql AS
$$
DECLARE
  v_requester bigint;
  v_status    text;
BEGIN
  SELECT requester_app_user_id, gig_request_status_code INTO v_requester, v_status
    FROM gig.gig_request WHERE id = NEW.gig_request_id;

  IF TG_OP = 'INSERT' THEN
    IF v_status <> 'open' THEN
      RAISE EXCEPTION 'trg_gig_application_blacklist: gig request % is not open', NEW.gig_request_id USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM gig.gig_requester_worker_list l
                WHERE l.requester_app_user_id = v_requester AND l.gig_worker_profile_id = NEW.gig_worker_profile_id
                  AND l.worker_list_kind_code = 'blacklist') THEN
      RAISE EXCEPTION 'trg_gig_application_blacklist: worker % is blacklisted by the requester', NEW.gig_worker_profile_id
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.gig_application_status_code <> 'applied' THEN
      RAISE EXCEPTION 'trg_gig_application_decision: a new gig application must start as applied' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.gig_application_status_code IS DISTINCT FROM OLD.gig_application_status_code THEN
    IF OLD.gig_application_status_code <> 'applied' THEN
      RAISE EXCEPTION 'trg_gig_application_decision: application already %', OLD.gig_application_status_code USING ERRCODE = 'check_violation';
    END IF;
    -- bids do not flow both ways: only the requester accepts or rejects; only the worker withdraws
    IF NEW.gig_application_status_code IN ('accepted', 'rejected')
       AND public.current_actor_id() IS DISTINCT FROM v_requester THEN
      RAISE EXCEPTION 'trg_gig_application_decision: only the requester can % an application', NEW.gig_application_status_code
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.gig_application_status_code = 'withdrawn'
       AND public.current_actor_id() IS DISTINCT FROM (SELECT app_user_id FROM gig.gig_worker_profile WHERE id = NEW.gig_worker_profile_id) THEN
      RAISE EXCEPTION 'trg_gig_application_decision: only the worker can withdraw an application' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_gig_application_blacklist BEFORE INSERT OR UPDATE OF gig_application_status_code ON gig.gig_application
  FOR EACH ROW EXECUTE FUNCTION gig.check_gig_application();

CREATE FUNCTION gig.check_gig_assignment() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM gig.gig_application WHERE id = NEW.gig_application_id AND gig_application_status_code = 'accepted') THEN
    RAISE EXCEPTION 'trg_gig_assignment_accepted: application % is not accepted', NEW.gig_application_id USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_gig_assignment_accepted BEFORE INSERT ON gig.gig_assignment
  FOR EACH ROW EXECUTE FUNCTION gig.check_gig_assignment();

CREATE FUNCTION gig.check_gig_rating() RETURNS trigger
LANGUAGE plpgsql AS
$$
DECLARE
  v_status    text;
  v_requester bigint;
BEGIN
  SELECT a.gig_assignment_status_code, r.requester_app_user_id INTO v_status, v_requester
    FROM gig.gig_assignment a JOIN gig.gig_request r ON r.id = a.gig_request_id
   WHERE a.id = NEW.gig_assignment_id;
  IF v_status <> 'completed' THEN
    RAISE EXCEPTION 'trg_gig_rating_completed_assignment: assignment % is %, only completed gigs can be rated',
                    NEW.gig_assignment_id, v_status USING ERRCODE = 'check_violation';
  END IF;
  IF public.current_actor_id() IS DISTINCT FROM v_requester THEN
    RAISE EXCEPTION 'trg_gig_rating_completed_assignment: only the requester rates a gig' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_gig_rating_completed_assignment BEFORE INSERT ON gig.gig_rating
  FOR EACH ROW EXECUTE FUNCTION gig.check_gig_rating();
