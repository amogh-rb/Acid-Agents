-- Sourcing and consultant requests (schema src). Owner B. Phase 3: M11-M14 (B37, B40, B43, B46).
-- Entities and relationships: docs/phase3/src_entities.md, src_relationships.md.
-- Rules:
--   * B46: a consultant may only request to source for a job open to consultants, and must hold the consultant role
--     (trg_sourcing_request_consultant_open)
--   * only a recruiter or employer of the job's organisation accepts or declines; decision columns agree with the
--     status; a decline needs a reason
--   * bulk outreach is idempotent per batch; one recipient row per candidate per batch; a candidate who blocked the
--     sender (user or organisation) cannot be contacted (trg_outreach_recipient_not_blocked)
--   * recruiters contact candidates but never register them (docket Section 3): outreach references existing profiles only

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
SELECT ref.create_lookup('ref.sourcing_request_status', 'state of a consultant sourcing request');
SELECT ref.add_lookup_value('ref.sourcing_request_status', 'requested', 'Requested', 1);
SELECT ref.add_lookup_value('ref.sourcing_request_status', 'accepted',  'Accepted',  2);
SELECT ref.add_lookup_value('ref.sourcing_request_status', 'declined',  'Declined',  3);
SELECT ref.add_lookup_value('ref.sourcing_request_status', 'withdrawn', 'Withdrawn', 4);
SELECT ref.add_lookup_value('ref.sourcing_request_status', 'closed',    'Closed',    5);

SELECT ref.create_lookup('ref.outreach_channel', 'channel of a bulk outreach');
SELECT ref.add_lookup_value('ref.outreach_channel', 'email',    'Email',    1);
SELECT ref.add_lookup_value('ref.outreach_channel', 'sms',      'SMS',      2);
SELECT ref.add_lookup_value('ref.outreach_channel', 'whatsapp', 'WhatsApp', 3);
SELECT ref.add_lookup_value('ref.outreach_channel', 'in_app',   'In-app',   4);

SELECT ref.create_lookup('ref.outreach_recipient_status', 'delivery state of one outreach recipient');
SELECT ref.add_lookup_value('ref.outreach_recipient_status', 'queued',    'Queued',    1);
SELECT ref.add_lookup_value('ref.outreach_recipient_status', 'sent',      'Sent',      2);
SELECT ref.add_lookup_value('ref.outreach_recipient_status', 'delivered', 'Delivered', 3);
SELECT ref.add_lookup_value('ref.outreach_recipient_status', 'failed',    'Failed',    4);
SELECT ref.add_lookup_value('ref.outreach_recipient_status', 'replied',   'Replied',   5);
SELECT ref.add_lookup_value('ref.outreach_recipient_status', 'opted_out', 'Opted out', 6);

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE src.sourcing_request (
  id                            bigint GENERATED ALWAYS AS IDENTITY,
  job_requirement_id            bigint        NOT NULL,
  consultant_app_user_id        bigint        NOT NULL,
  consultant_organisation_id    bigint,
  sourcing_request_status_code  d_code        NOT NULL DEFAULT 'requested',
  request_note                  varchar(1000),
  requested_at                  timestamptz   NOT NULL DEFAULT now(),
  decided_by_app_user_id        bigint,
  decided_at                    timestamptz,
  decline_reason                varchar(500),
  created_at                    timestamptz   NOT NULL DEFAULT now(),
  created_by                    bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at                    timestamptz   NOT NULL DEFAULT now(),
  updated_by                    bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_sourcing_request PRIMARY KEY (id),
  CONSTRAINT uq_sourcing_request_id_job_requirement_id UNIQUE (id, job_requirement_id),
  CONSTRAINT fk_sourcing_request_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_sourcing_request_consultant_app_user_id FOREIGN KEY (consultant_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_sourcing_request_consultant_organisation_id FOREIGN KEY (consultant_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_sourcing_request_sourcing_request_status_code FOREIGN KEY (sourcing_request_status_code) REFERENCES ref.sourcing_request_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_sourcing_request_decided_by_app_user_id FOREIGN KEY (decided_by_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_sourcing_request_decision CHECK (
    (sourcing_request_status_code IN ('accepted', 'declined')) = (decided_by_app_user_id IS NOT NULL AND decided_at IS NOT NULL)),
  CONSTRAINT ck_sourcing_request_decline_reason CHECK (
    (sourcing_request_status_code = 'declined') = (decline_reason IS NOT NULL AND btrim(decline_reason) <> '')),
  CONSTRAINT ck_sourcing_request_decided_after_request CHECK (decided_at IS NULL OR decided_at >= requested_at)
);
-- one live request per consultant per job
CREATE UNIQUE INDEX uq_sourcing_request_live_per_consultant ON src.sourcing_request (job_requirement_id, consultant_app_user_id)
  WHERE sourcing_request_status_code IN ('requested', 'accepted');
CREATE INDEX idx_sourcing_request_consultant_app_user_id ON src.sourcing_request (consultant_app_user_id, sourcing_request_status_code);
CREATE INDEX idx_sourcing_request_consultant_organisation_id ON src.sourcing_request (consultant_organisation_id) WHERE consultant_organisation_id IS NOT NULL;
CREATE INDEX idx_sourcing_request_decided_by_app_user_id ON src.sourcing_request (decided_by_app_user_id) WHERE decided_by_app_user_id IS NOT NULL;
COMMENT ON TABLE  src.sourcing_request IS '[hard-delete] Consultant request to source candidates for a job; the employer accepts or declines';
COMMENT ON COLUMN src.sourcing_request.job_requirement_id IS '[Internal] Job to source for (must be open to consultants)';
COMMENT ON COLUMN src.sourcing_request.consultant_app_user_id IS '[Internal] Requesting consultant (must hold the consultant role)';
COMMENT ON COLUMN src.sourcing_request.consultant_organisation_id IS '[Internal] Consultancy the consultant works for; null: freelance consultant';
COMMENT ON COLUMN src.sourcing_request.sourcing_request_status_code IS '[Internal] requested, accepted, declined, withdrawn, closed; default requested';
COMMENT ON COLUMN src.sourcing_request.request_note IS '[Internal] Pitch to the employer, max 1000; null: none';
COMMENT ON COLUMN src.sourcing_request.requested_at IS '[Internal] Request instant (UTC)';
COMMENT ON COLUMN src.sourcing_request.decided_by_app_user_id IS '[Internal] Employer user who accepted or declined; null: not decided yet';
COMMENT ON COLUMN src.sourcing_request.decided_at IS '[Internal] Decision instant (UTC); null: not decided yet';
COMMENT ON COLUMN src.sourcing_request.decline_reason IS '[Internal] Why declined, max 500; null: not declined';

CREATE FUNCTION src.check_sourcing_request() RETURNS trigger
LANGUAGE plpgsql AS
$$
DECLARE
  v_job job.job_requirement;
BEGIN
  SELECT * INTO v_job FROM job.job_requirement WHERE id = NEW.job_requirement_id;
  IF TG_OP = 'INSERT' THEN
    IF NOT v_job.is_open_to_consultant OR v_job.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'trg_sourcing_request_consultant_open: job requirement % is not open to consultants', NEW.job_requirement_id
        USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM admin.user_role r
                    WHERE r.app_user_id = NEW.consultant_app_user_id AND r.app_role_code = 'consultant'
                      AND r.valid_period @> now()) THEN
      RAISE EXCEPTION 'trg_sourcing_request_consultant_open: user % does not hold the consultant role', NEW.consultant_app_user_id
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.sourcing_request_status_code IN ('accepted', 'declined')
        AND NEW.sourcing_request_status_code IS DISTINCT FROM OLD.sourcing_request_status_code
        AND NEW.decided_by_app_user_id IS NOT NULL THEN        -- a missing decider is left to ck_sourcing_request_decision
    -- only someone acting for the job's organisation decides
    IF NOT EXISTS (SELECT 1 FROM admin.user_role r
                    WHERE r.app_user_id = NEW.decided_by_app_user_id AND r.app_role_code IN ('employer', 'recruiter')
                      AND r.organisation_id = v_job.organisation_id AND r.valid_period @> now())
       AND org.current_recruiter_organisation(NEW.decided_by_app_user_id) IS DISTINCT FROM v_job.organisation_id THEN
      RAISE EXCEPTION 'trg_sourcing_request_consultant_open: user % cannot decide for organisation %',
                      NEW.decided_by_app_user_id, v_job.organisation_id USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_sourcing_request_consultant_open BEFORE INSERT OR UPDATE OF sourcing_request_status_code ON src.sourcing_request
  FOR EACH ROW EXECUTE FUNCTION src.check_sourcing_request();

-- ---------------------------------------------------------------------------------------------------
-- Candidate shortlists built for a sourcing request reuse the Jobs shortlist (one owner of shortlist data)
ALTER TABLE job.shortlist ADD CONSTRAINT uq_shortlist_id_job_requirement_id UNIQUE (id, job_requirement_id);

CREATE TABLE src.sourcing_shortlist (
  id                   bigint GENERATED ALWAYS AS IDENTITY,
  sourcing_request_id  bigint      NOT NULL,
  shortlist_id         bigint      NOT NULL,
  job_requirement_id   bigint      NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by           bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  updated_by           bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_sourcing_shortlist PRIMARY KEY (id),
  CONSTRAINT uq_sourcing_shortlist_sourcing_request_id_shortlist_id UNIQUE (sourcing_request_id, shortlist_id),
  CONSTRAINT fk_sourcing_shortlist_sourcing_request_id FOREIGN KEY (sourcing_request_id) REFERENCES src.sourcing_request (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_sourcing_shortlist_shortlist_id FOREIGN KEY (shortlist_id) REFERENCES job.shortlist (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_sourcing_shortlist_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  -- request and shortlist must be for the same job
  CONSTRAINT fk_sourcing_shortlist_request_job FOREIGN KEY (sourcing_request_id, job_requirement_id)
    REFERENCES src.sourcing_request (id, job_requirement_id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_sourcing_shortlist_shortlist_job FOREIGN KEY (shortlist_id, job_requirement_id)
    REFERENCES job.shortlist (id, job_requirement_id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_sourcing_shortlist_shortlist_id ON src.sourcing_shortlist (shortlist_id);
CREATE INDEX idx_sourcing_shortlist_job_requirement_id ON src.sourcing_shortlist (job_requirement_id);
COMMENT ON TABLE  src.sourcing_shortlist IS '[hard-delete] Links a sourcing request to the job shortlist the consultant fills (owned by the request); the shortlist itself lives in job.shortlist';
COMMENT ON COLUMN src.sourcing_shortlist.sourcing_request_id IS '[Internal] Sourcing request';
COMMENT ON COLUMN src.sourcing_shortlist.shortlist_id IS '[Internal] Shortlist in the Jobs module';
COMMENT ON COLUMN src.sourcing_shortlist.job_requirement_id IS '[Internal] Job of both the request and the shortlist (checked by two composite FKs)';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE src.outreach_batch (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  sender_app_user_id       bigint       NOT NULL,
  sender_organisation_id   bigint,
  job_requirement_id       bigint,
  sourcing_request_id      bigint,
  outreach_channel_code    d_code       NOT NULL,
  message_template_key     varchar(150) NOT NULL,
  idempotency_key          varchar(64)  NOT NULL,
  requested_at             timestamptz  NOT NULL DEFAULT now(),
  created_at               timestamptz  NOT NULL DEFAULT now(),
  created_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz  NOT NULL DEFAULT now(),
  updated_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_outreach_batch PRIMARY KEY (id),
  CONSTRAINT uq_outreach_batch_idempotency_key UNIQUE (idempotency_key),
  CONSTRAINT fk_outreach_batch_sender_app_user_id FOREIGN KEY (sender_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_outreach_batch_sender_organisation_id FOREIGN KEY (sender_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_outreach_batch_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_outreach_batch_sourcing_request_id FOREIGN KEY (sourcing_request_id) REFERENCES src.sourcing_request (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_outreach_batch_outreach_channel_code FOREIGN KEY (outreach_channel_code) REFERENCES ref.outreach_channel (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_outreach_batch_message_template_key_format CHECK (message_template_key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$')
);
CREATE INDEX idx_outreach_batch_sender_app_user_id ON src.outreach_batch (sender_app_user_id, requested_at);
CREATE INDEX idx_outreach_batch_sender_organisation_id ON src.outreach_batch (sender_organisation_id) WHERE sender_organisation_id IS NOT NULL;
CREATE INDEX idx_outreach_batch_job_requirement_id ON src.outreach_batch (job_requirement_id) WHERE job_requirement_id IS NOT NULL;
CREATE INDEX idx_outreach_batch_sourcing_request_id ON src.outreach_batch (sourcing_request_id) WHERE sourcing_request_id IS NOT NULL;
COMMENT ON TABLE  src.outreach_batch IS '[hard-delete] Bulk outreach by a recruiter, employer or consultant to existing candidates. Message bodies are not stored (template key only; docket Section 6)';
COMMENT ON COLUMN src.outreach_batch.sender_app_user_id IS '[Internal] User sending the outreach';
COMMENT ON COLUMN src.outreach_batch.sender_organisation_id IS '[Internal] Organisation the sender acts for; null: freelance consultant';
COMMENT ON COLUMN src.outreach_batch.job_requirement_id IS '[Internal] Job the outreach is about; null: general talent-pool outreach';
COMMENT ON COLUMN src.outreach_batch.sourcing_request_id IS '[Internal] Sourcing request it belongs to; null: employer outreach, not a consultant engagement';
COMMENT ON COLUMN src.outreach_batch.outreach_channel_code IS '[Internal] email, sms, whatsapp, in_app';
COMMENT ON COLUMN src.outreach_batch.message_template_key IS '[Internal] UI/message template key (the body is rendered by the provider), max 150';
COMMENT ON COLUMN src.outreach_batch.idempotency_key IS '[Internal] Client key so a retried send creates one batch';
COMMENT ON COLUMN src.outreach_batch.requested_at IS '[Internal] When the send was requested (UTC)';

CREATE TABLE src.outreach_recipient (
  id                              bigint GENERATED ALWAYS AS IDENTITY,
  outreach_batch_id               bigint       NOT NULL,
  candidate_profile_id            bigint       NOT NULL,
  outreach_recipient_status_code  d_code       NOT NULL DEFAULT 'queued',
  provider_message_reference      varchar(100),
  sent_at                         timestamptz,
  delivered_at                    timestamptz,
  created_at                      timestamptz  NOT NULL DEFAULT now(),
  created_by                      bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                      timestamptz  NOT NULL DEFAULT now(),
  updated_by                      bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_outreach_recipient PRIMARY KEY (id),
  CONSTRAINT uq_outreach_recipient_batch_candidate UNIQUE (outreach_batch_id, candidate_profile_id),
  CONSTRAINT uq_outreach_recipient_provider_message_reference UNIQUE (provider_message_reference),
  CONSTRAINT fk_outreach_recipient_outreach_batch_id FOREIGN KEY (outreach_batch_id) REFERENCES src.outreach_batch (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_outreach_recipient_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_outreach_recipient_outreach_recipient_status_code FOREIGN KEY (outreach_recipient_status_code) REFERENCES ref.outreach_recipient_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_outreach_recipient_sent CHECK (outreach_recipient_status_code IN ('queued', 'failed', 'opted_out') OR sent_at IS NOT NULL),
  CONSTRAINT ck_outreach_recipient_delivered CHECK (delivered_at IS NULL OR (sent_at IS NOT NULL AND delivered_at >= sent_at))
);
CREATE INDEX idx_outreach_recipient_candidate_profile_id ON src.outreach_recipient (candidate_profile_id);
COMMENT ON TABLE  src.outreach_recipient IS '[hard-delete] One candidate in an outreach batch and the delivery state (owned by the batch)';
COMMENT ON COLUMN src.outreach_recipient.outreach_batch_id IS '[Internal] Batch';
COMMENT ON COLUMN src.outreach_recipient.candidate_profile_id IS '[Internal] Candidate contacted (an existing profile; recruiters cannot register candidates)';
COMMENT ON COLUMN src.outreach_recipient.outreach_recipient_status_code IS '[Internal] queued, sent, delivered, failed, replied, opted_out; default queued';
COMMENT ON COLUMN src.outreach_recipient.provider_message_reference IS '[Internal] Message id from the messaging provider (unique, idempotent callbacks); null: not handed to the provider yet';
COMMENT ON COLUMN src.outreach_recipient.sent_at IS '[Internal] Handed to the provider (UTC); null: not sent';
COMMENT ON COLUMN src.outreach_recipient.delivered_at IS '[Internal] Provider delivery receipt (UTC); null: not delivered (yet)';

-- a candidate who blocked the sender (user or organisation) cannot be contacted (docket Section 3)
CREATE FUNCTION src.check_outreach_recipient() RETURNS trigger
LANGUAGE plpgsql AS
$$
DECLARE
  v_sender     bigint;
  v_sender_org bigint;
BEGIN
  SELECT sender_app_user_id, sender_organisation_id INTO v_sender, v_sender_org
    FROM src.outreach_batch WHERE id = NEW.outreach_batch_id;
  IF EXISTS (SELECT 1
               FROM profile.candidate_profile cp
               JOIN admin.block_list b ON b.blocker_app_user_id = cp.app_user_id AND b.deleted_at IS NULL
              WHERE cp.id = NEW.candidate_profile_id
                AND (b.blocked_app_user_id = v_sender OR b.blocked_organisation_id = v_sender_org)) THEN
    RAISE EXCEPTION 'trg_outreach_recipient_not_blocked: candidate profile % has blocked the sender', NEW.candidate_profile_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_outreach_recipient_not_blocked BEFORE INSERT ON src.outreach_recipient
  FOR EACH ROW EXECUTE FUNCTION src.check_outreach_recipient();
