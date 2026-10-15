-- Notifications, preferences and community (schema notif). Owner B. Phase 4: M15-M18 (B48, B51, B54, B57).
-- Entities and relationships: docs/phase4/notif_entities.md, notif_relationships.md.
--   * preferences: per-event/channel notification switches, job alerts, UI language, time zone and privacy settings
--   * notifications store a message key + parameters, never message bodies (docket Section 6)
--   * high-volume write path (B57): notif.notification_delivery is RANGE-partitioned by month on queued_at
--     (<table>_pYYYYMM + _default); old months are detached and dropped for retention, not deleted row by row.
--     Provider message ids are deduplicated globally in notif.delivery_provider_receipt (a unique key on a
--     partitioned table must include the partition key, so it cannot be global there)
--   * community posts/reactions, support tickets and FAQs are modelled thinly (Tier 2; decision in 00_decisions)

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
SELECT ref.create_lookup('ref.notification_channel', 'channel a notification is delivered on');
SELECT ref.add_lookup_value('ref.notification_channel', 'email',    'Email',    1);
SELECT ref.add_lookup_value('ref.notification_channel', 'sms',      'SMS',      2);
SELECT ref.add_lookup_value('ref.notification_channel', 'whatsapp', 'WhatsApp', 3);
SELECT ref.add_lookup_value('ref.notification_channel', 'push',     'Push',     4);
SELECT ref.add_lookup_value('ref.notification_channel', 'in_app',   'In-app',   5);

SELECT ref.create_lookup('ref.notification_event_type', 'event that triggers a notification');
SELECT ref.add_lookup_value('ref.notification_event_type', 'application_status', 'Application status changed', 1);
SELECT ref.add_lookup_value('ref.notification_event_type', 'interview_scheduled', 'Interview scheduled',     2);
SELECT ref.add_lookup_value('ref.notification_event_type', 'job_alert',          'Job alert',                3);
SELECT ref.add_lookup_value('ref.notification_event_type', 'recruiter_message',  'Recruiter message',        4);
SELECT ref.add_lookup_value('ref.notification_event_type', 'gig_update',         'Gig update',               5);
SELECT ref.add_lookup_value('ref.notification_event_type', 'billing',            'Billing',                  6);
SELECT ref.add_lookup_value('ref.notification_event_type', 'security',           'Security alert',           7);

SELECT ref.create_lookup('ref.delivery_status', 'delivery state of a notification on one channel');
SELECT ref.add_lookup_value('ref.delivery_status', 'queued',    'Queued',    1);
SELECT ref.add_lookup_value('ref.delivery_status', 'sent',      'Sent',      2);
SELECT ref.add_lookup_value('ref.delivery_status', 'delivered', 'Delivered', 3);
SELECT ref.add_lookup_value('ref.delivery_status', 'opened',    'Opened',    4);
SELECT ref.add_lookup_value('ref.delivery_status', 'failed',    'Failed',    5);
SELECT ref.add_lookup_value('ref.delivery_status', 'suppressed', 'Suppressed by preference', 6);

SELECT ref.create_lookup('ref.alert_frequency', 'how often a job alert is sent');
SELECT ref.add_lookup_value('ref.alert_frequency', 'instant', 'Instant', 1);
SELECT ref.add_lookup_value('ref.alert_frequency', 'daily',   'Daily',   2);
SELECT ref.add_lookup_value('ref.alert_frequency', 'weekly',  'Weekly',  3);

SELECT ref.create_lookup('ref.profile_visibility', 'who may find a candidate profile');
SELECT ref.add_lookup_value('ref.profile_visibility', 'all_employers',  'All employers and recruiters', 1);
SELECT ref.add_lookup_value('ref.profile_visibility', 'applied_only',   'Only employers I applied to', 2);
SELECT ref.add_lookup_value('ref.profile_visibility', 'hidden',         'Hidden',                       3);

SELECT ref.create_lookup('ref.reaction_type', 'reaction to a community post');
SELECT ref.add_lookup_value('ref.reaction_type', 'like',       'Like',       1);
SELECT ref.add_lookup_value('ref.reaction_type', 'celebrate',  'Celebrate',  2);
SELECT ref.add_lookup_value('ref.reaction_type', 'insightful', 'Insightful', 3);

SELECT ref.create_lookup('ref.ticket_category', 'support ticket category');
SELECT ref.add_lookup_value('ref.ticket_category', 'account',  'Account and login', 1);
SELECT ref.add_lookup_value('ref.ticket_category', 'billing',  'Billing',           2);
SELECT ref.add_lookup_value('ref.ticket_category', 'job_post', 'Job posting',       3);
SELECT ref.add_lookup_value('ref.ticket_category', 'other',    'Other',             4);

SELECT ref.create_lookup('ref.ticket_status', 'support ticket status');
SELECT ref.add_lookup_value('ref.ticket_status', 'open',        'Open',        1);
SELECT ref.add_lookup_value('ref.ticket_status', 'in_progress', 'In progress', 2);
SELECT ref.add_lookup_value('ref.ticket_status', 'resolved',    'Resolved',    3);
SELECT ref.add_lookup_value('ref.ticket_status', 'closed',      'Closed',      4);

-- ---------------------------------------------------------------------------------------------------
-- Preferences
CREATE TABLE notif.user_preference (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id              bigint      NOT NULL,
  ui_language_id           bigint      NOT NULL,
  timezone_id              bigint,
  profile_visibility_code  d_code      NOT NULL DEFAULT 'all_employers',
  show_salary_to_recruiters boolean    NOT NULL DEFAULT false,
  allow_recruiter_contact  boolean     NOT NULL DEFAULT true,
  created_at               timestamptz NOT NULL DEFAULT now(),
  created_by               bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  updated_by               bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_user_preference PRIMARY KEY (id),
  CONSTRAINT uq_user_preference_app_user_id UNIQUE (app_user_id),
  CONSTRAINT fk_user_preference_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_user_preference_ui_language_id FOREIGN KEY (ui_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_user_preference_timezone_id FOREIGN KEY (timezone_id) REFERENCES ref.timezone (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_user_preference_profile_visibility_code FOREIGN KEY (profile_visibility_code) REFERENCES ref.profile_visibility (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  notif.user_preference IS '[hard-delete] Language preference and privacy settings of a user (owned by app_user); a missing row means the defaults (default language, all employers)';
COMMENT ON COLUMN notif.user_preference.app_user_id IS '[Internal] User (one row per user)';
COMMENT ON COLUMN notif.user_preference.ui_language_id IS '[Internal] UI language; ref.ui_text falls back to the default language when a label is untranslated';
COMMENT ON COLUMN notif.user_preference.timezone_id IS '[Internal] Display time zone; null: use the city or browser time zone';
COMMENT ON COLUMN notif.user_preference.profile_visibility_code IS '[Internal] Privacy: who may find the profile; default all_employers';
COMMENT ON COLUMN notif.user_preference.show_salary_to_recruiters IS '[Internal] Privacy: disclose salary fields to recruiters; default false';
COMMENT ON COLUMN notif.user_preference.allow_recruiter_contact IS '[Internal] Privacy: recruiters may message the user; default true';

-- the UI language must be one the UI supports
CREATE FUNCTION notif.check_user_preference_language() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  IF NOT (SELECT is_ui_supported FROM ref.language WHERE id = NEW.ui_language_id) THEN
    RAISE EXCEPTION 'trg_user_preference_ui_language: language % is not a supported UI language', NEW.ui_language_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_user_preference_ui_language BEFORE INSERT OR UPDATE OF ui_language_id ON notif.user_preference
  FOR EACH ROW EXECUTE FUNCTION notif.check_user_preference_language();

CREATE TABLE notif.notification_preference (
  id                            bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id                   bigint      NOT NULL,
  notification_event_type_code  d_code      NOT NULL,
  notification_channel_code     d_code      NOT NULL,
  is_enabled                    boolean     NOT NULL DEFAULT true,
  created_at                    timestamptz NOT NULL DEFAULT now(),
  created_by                    bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                    timestamptz NOT NULL DEFAULT now(),
  updated_by                    bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_notification_preference PRIMARY KEY (id),
  CONSTRAINT uq_notification_preference_user_event_channel UNIQUE (app_user_id, notification_event_type_code, notification_channel_code),
  CONSTRAINT fk_notification_preference_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_notification_preference_notification_event_type_code FOREIGN KEY (notification_event_type_code) REFERENCES ref.notification_event_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_notification_preference_notification_channel_code FOREIGN KEY (notification_channel_code) REFERENCES ref.notification_channel (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  notif.notification_preference IS '[hard-delete] Per-event, per-channel notification switch (owned by app_user); a missing row means enabled';
COMMENT ON COLUMN notif.notification_preference.app_user_id IS '[Internal] User';
COMMENT ON COLUMN notif.notification_preference.notification_event_type_code IS '[Internal] Event type';
COMMENT ON COLUMN notif.notification_preference.notification_channel_code IS '[Internal] Channel';
COMMENT ON COLUMN notif.notification_preference.is_enabled IS '[Internal] Deliver this event on this channel; default true';

CREATE TABLE notif.job_alert (
  id                         bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id       bigint      NOT NULL,
  saved_search_id            bigint      NOT NULL,
  alert_frequency_code       d_code      NOT NULL DEFAULT 'daily',
  notification_channel_code  d_code      NOT NULL DEFAULT 'email',
  is_active                  boolean     NOT NULL DEFAULT true,
  last_sent_at               timestamptz,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  created_by                 bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                 timestamptz NOT NULL DEFAULT now(),
  updated_by                 bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_alert PRIMARY KEY (id),
  CONSTRAINT uq_job_alert_saved_search_id_channel UNIQUE (saved_search_id, notification_channel_code),
  CONSTRAINT fk_job_alert_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_job_alert_saved_search_id FOREIGN KEY (saved_search_id) REFERENCES job.saved_search (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_job_alert_alert_frequency_code FOREIGN KEY (alert_frequency_code) REFERENCES ref.alert_frequency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_alert_notification_channel_code FOREIGN KEY (notification_channel_code) REFERENCES ref.notification_channel (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_job_alert_candidate_profile_id ON notif.job_alert (candidate_profile_id);
CREATE INDEX idx_job_alert_due ON notif.job_alert (alert_frequency_code, last_sent_at) WHERE is_active;
COMMENT ON TABLE  notif.job_alert IS '[hard-delete] Job alert preference: send matches of a saved search at a frequency on a channel (owned by the candidate)';
COMMENT ON COLUMN notif.job_alert.candidate_profile_id IS '[Internal] Candidate receiving the alert';
COMMENT ON COLUMN notif.job_alert.saved_search_id IS '[Internal] Saved search whose matches are sent';
COMMENT ON COLUMN notif.job_alert.alert_frequency_code IS '[Internal] instant, daily, weekly; default daily';
COMMENT ON COLUMN notif.job_alert.notification_channel_code IS '[Internal] Channel; default email';
COMMENT ON COLUMN notif.job_alert.is_active IS '[Internal] Alert switched on; default true';
COMMENT ON COLUMN notif.job_alert.last_sent_at IS '[Internal] Last digest sent (UTC); null: never sent';

-- ---------------------------------------------------------------------------------------------------
-- Notifications and deliveries
CREATE TABLE notif.notification (
  id                            bigint GENERATED ALWAYS AS IDENTITY,
  recipient_app_user_id         bigint       NOT NULL,
  notification_event_type_code  d_code       NOT NULL,
  message_label_key             varchar(150) NOT NULL,
  message_parameters            jsonb,
  read_at                       timestamptz,
  created_at                    timestamptz  NOT NULL DEFAULT now(),
  created_by                    bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                    timestamptz  NOT NULL DEFAULT now(),
  updated_by                    bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_notification PRIMARY KEY (id),
  CONSTRAINT fk_notification_recipient_app_user_id FOREIGN KEY (recipient_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_notification_notification_event_type_code FOREIGN KEY (notification_event_type_code) REFERENCES ref.notification_event_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_notification_message_label_key FOREIGN KEY (message_label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX idx_notification_recipient_app_user_id ON notif.notification (recipient_app_user_id, created_at DESC);
CREATE INDEX idx_notification_unread ON notif.notification (recipient_app_user_id) WHERE read_at IS NULL;
COMMENT ON TABLE  notif.notification IS '[hard-delete] Notification for a user: a translatable message key plus parameters, rendered per language at send time; no message bodies stored (owned by app_user). Retention: 180 days';
COMMENT ON COLUMN notif.notification.recipient_app_user_id IS '[Internal] Recipient';
COMMENT ON COLUMN notif.notification.notification_event_type_code IS '[Internal] Triggering event';
COMMENT ON COLUMN notif.notification.message_label_key IS '[Internal] UI label key of the message template';
COMMENT ON COLUMN notif.notification.message_parameters IS '[Personal] Template parameters (job title, interview time); null: template has none';
COMMENT ON COLUMN notif.notification.read_at IS '[Internal] When the user read it in-app (UTC); null: unread';

CREATE TABLE notif.notification_delivery (
  id                         bigint GENERATED ALWAYS AS IDENTITY,
  notification_id            bigint       NOT NULL,
  notification_channel_code  d_code       NOT NULL,
  delivery_status_code       d_code       NOT NULL DEFAULT 'queued',
  queued_at                  timestamptz  NOT NULL DEFAULT now(),
  sent_at                    timestamptz,
  delivered_at               timestamptz,
  failure_reason             varchar(300),
  created_at                 timestamptz  NOT NULL DEFAULT now(),
  created_by                 bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                 timestamptz  NOT NULL DEFAULT now(),
  updated_by                 bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_notification_delivery PRIMARY KEY (id, queued_at),
  CONSTRAINT uq_notification_delivery_notification_channel UNIQUE (notification_id, notification_channel_code, queued_at),
  CONSTRAINT fk_notification_delivery_notification_id FOREIGN KEY (notification_id) REFERENCES notif.notification (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_notification_delivery_notification_channel_code FOREIGN KEY (notification_channel_code) REFERENCES ref.notification_channel (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_notification_delivery_delivery_status_code FOREIGN KEY (delivery_status_code) REFERENCES ref.delivery_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_notification_delivery_sent CHECK (delivery_status_code NOT IN ('sent', 'delivered', 'opened') OR sent_at IS NOT NULL),
  CONSTRAINT ck_notification_delivery_failure CHECK ((delivery_status_code = 'failed') = (failure_reason IS NOT NULL)),
  CONSTRAINT ck_notification_delivery_time_range CHECK ((sent_at IS NULL OR sent_at >= queued_at) AND (delivered_at IS NULL OR delivered_at >= sent_at))
) PARTITION BY RANGE (queued_at);
CREATE INDEX idx_notification_delivery_notification_id ON notif.notification_delivery (notification_id);
CREATE INDEX idx_notification_delivery_pending ON notif.notification_delivery (queued_at) WHERE delivery_status_code = 'queued';
COMMENT ON TABLE  notif.notification_delivery IS '[hard-delete] Delivery of a notification on one channel and its status (high-volume write path). Monthly RANGE partitions on queued_at; retention = detach and drop months older than 13 months';
COMMENT ON COLUMN notif.notification_delivery.notification_id IS '[Internal] Notification delivered';
COMMENT ON COLUMN notif.notification_delivery.notification_channel_code IS '[Internal] Channel';
COMMENT ON COLUMN notif.notification_delivery.delivery_status_code IS '[Internal] queued, sent, delivered, opened, failed, suppressed; default queued';
COMMENT ON COLUMN notif.notification_delivery.queued_at IS '[Internal] When the delivery was queued (UTC); partition key';
COMMENT ON COLUMN notif.notification_delivery.sent_at IS '[Internal] Handed to the provider (UTC); null: not sent (queued, suppressed or failed before sending)';
COMMENT ON COLUMN notif.notification_delivery.delivered_at IS '[Internal] Provider delivery receipt (UTC); null: not delivered (yet)';
COMMENT ON COLUMN notif.notification_delivery.failure_reason IS '[Internal] Provider error, max 300; null: not failed';

-- Monthly partitions: created ahead by this function (scheduled monthly); the default partition catches strays.
CREATE FUNCTION notif.ensure_delivery_partitions(p_from date, p_months integer) RETURNS integer
LANGUAGE plpgsql AS
$$
DECLARE
  v_start   date := date_trunc('month', p_from)::date;
  v_created integer := 0;
  v_name    text;
BEGIN
  FOR i IN 0 .. p_months - 1 LOOP
    v_name := 'notification_delivery_p' || to_char(v_start + make_interval(months => i), 'YYYYMM');
    IF to_regclass('notif.' || v_name) IS NULL THEN
      EXECUTE format('CREATE TABLE notif.%I PARTITION OF notif.notification_delivery FOR VALUES FROM (%L) TO (%L)',
                     v_name, v_start + make_interval(months => i), v_start + make_interval(months => i + 1));
      v_created := v_created + 1;
    END IF;
  END LOOP;
  RETURN v_created;
END
$$;
SELECT notif.ensure_delivery_partitions(DATE '2026-01-01', 24);
CREATE TABLE notif.notification_delivery_default PARTITION OF notif.notification_delivery DEFAULT;

-- Global de-duplication of provider message ids (cannot be a unique key on the partitioned table)
CREATE TABLE notif.delivery_provider_receipt (
  id                          bigint GENERATED ALWAYS AS IDENTITY,
  notification_channel_code   d_code       NOT NULL,
  provider_message_reference  varchar(100) NOT NULL,
  notification_delivery_id    bigint       NOT NULL,
  delivery_queued_at          timestamptz  NOT NULL,
  received_at                 timestamptz  NOT NULL DEFAULT now(),
  created_at                  timestamptz  NOT NULL DEFAULT now(),
  created_by                  bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                  timestamptz  NOT NULL DEFAULT now(),
  updated_by                  bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_delivery_provider_receipt PRIMARY KEY (id),
  CONSTRAINT uq_delivery_provider_receipt_provider_message UNIQUE (notification_channel_code, provider_message_reference),
  CONSTRAINT uq_delivery_provider_receipt_delivery UNIQUE (notification_delivery_id, delivery_queued_at),
  CONSTRAINT fk_delivery_provider_receipt_notification_channel_code FOREIGN KEY (notification_channel_code) REFERENCES ref.notification_channel (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_delivery_provider_receipt_delivery FOREIGN KEY (notification_delivery_id, delivery_queued_at)
    REFERENCES notif.notification_delivery (id, queued_at) ON UPDATE NO ACTION ON DELETE CASCADE
);
COMMENT ON TABLE  notif.delivery_provider_receipt IS '[hard-delete] [integration-write] Provider message id assigned to a delivery; globally unique per channel, so a duplicate provider callback is rejected (idempotency). Dropped with its delivery partition';
COMMENT ON COLUMN notif.delivery_provider_receipt.notification_channel_code IS '[Internal] Channel / provider family';
COMMENT ON COLUMN notif.delivery_provider_receipt.provider_message_reference IS '[Internal] Message id returned by the provider, max 100';
COMMENT ON COLUMN notif.delivery_provider_receipt.notification_delivery_id IS '[Internal] Delivery the provider id belongs to (one per delivery); owned child of the delivery';
COMMENT ON COLUMN notif.delivery_provider_receipt.delivery_queued_at IS '[Internal] Partition key of the delivery (half of the composite FK)';
COMMENT ON COLUMN notif.delivery_provider_receipt.received_at IS '[Internal] When the provider id was recorded (UTC)';

-- ---------------------------------------------------------------------------------------------------
-- Community (Tier 2, thin)
CREATE TABLE notif.community_post (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  author_app_user_id     bigint        NOT NULL,
  post_body              varchar(4000) NOT NULL,
  post_body_language_id  bigint,
  posted_at              timestamptz   NOT NULL DEFAULT now(),
  created_at             timestamptz   NOT NULL DEFAULT now(),
  created_by             bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz   NOT NULL DEFAULT now(),
  updated_by             bigint        NOT NULL DEFAULT public.current_actor_id(),
  deleted_at             timestamptz,
  CONSTRAINT pk_community_post PRIMARY KEY (id),
  CONSTRAINT fk_community_post_author_app_user_id FOREIGN KEY (author_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_community_post_post_body_language_id FOREIGN KEY (post_body_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_community_post_post_body_not_blank CHECK (btrim(post_body) <> '')
);
CREATE INDEX idx_community_post_author_app_user_id ON notif.community_post (author_app_user_id, posted_at);
COMMENT ON TABLE  notif.community_post IS '[soft-delete] Community post by a user (moderation removes by soft delete)';
COMMENT ON COLUMN notif.community_post.author_app_user_id IS '[Internal] Author';
COMMENT ON COLUMN notif.community_post.post_body IS '[Personal] Post text as entered, max 4000';
COMMENT ON COLUMN notif.community_post.post_body_language_id IS '[Internal] Language of post_body; null: not detected (RG7)';
COMMENT ON COLUMN notif.community_post.posted_at IS '[Internal] Publication instant (UTC)';

CREATE TABLE notif.community_reaction (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  community_post_id   bigint      NOT NULL,
  app_user_id         bigint      NOT NULL,
  reaction_type_code  d_code      NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_community_reaction PRIMARY KEY (id),
  CONSTRAINT uq_community_reaction_community_post_id_app_user_id UNIQUE (community_post_id, app_user_id),
  CONSTRAINT fk_community_reaction_community_post_id FOREIGN KEY (community_post_id) REFERENCES notif.community_post (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_community_reaction_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_community_reaction_reaction_type_code FOREIGN KEY (reaction_type_code) REFERENCES ref.reaction_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_community_reaction_app_user_id ON notif.community_reaction (app_user_id);
COMMENT ON TABLE  notif.community_reaction IS '[hard-delete] One user reaction to a post (owned by the post); one per user per post';
COMMENT ON COLUMN notif.community_reaction.community_post_id IS '[Internal] Post';
COMMENT ON COLUMN notif.community_reaction.app_user_id IS '[Internal] Reacting user';
COMMENT ON COLUMN notif.community_reaction.reaction_type_code IS '[Public] like, celebrate, insightful';

-- ---------------------------------------------------------------------------------------------------
-- Support (Tier 2, thin)
CREATE TABLE notif.faq (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  question_label_key  varchar(150) NOT NULL,
  answer_label_key    varchar(150) NOT NULL,
  ticket_category_code d_code      NOT NULL,
  is_published        boolean      NOT NULL DEFAULT false,
  sort_order          integer      NOT NULL DEFAULT 0,
  created_at          timestamptz  NOT NULL DEFAULT now(),
  created_by          bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at          timestamptz  NOT NULL DEFAULT now(),
  updated_by          bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_faq PRIMARY KEY (id),
  CONSTRAINT uq_faq_question_label_key UNIQUE (question_label_key),
  CONSTRAINT fk_faq_question_label_key FOREIGN KEY (question_label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_faq_answer_label_key FOREIGN KEY (answer_label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_faq_ticket_category_code FOREIGN KEY (ticket_category_code) REFERENCES ref.ticket_category (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_faq_sort_order CHECK (sort_order >= 0)
);
COMMENT ON TABLE  notif.faq IS '[hard-delete] FAQ entry; question and answer are UI labels, so they are translated like any other UI text (RG7)';
COMMENT ON COLUMN notif.faq.question_label_key IS '[Public] UI label key of the question';
COMMENT ON COLUMN notif.faq.answer_label_key IS '[Public] UI label key of the answer';
COMMENT ON COLUMN notif.faq.ticket_category_code IS '[Public] Topic, shared with support tickets';
COMMENT ON COLUMN notif.faq.is_published IS '[Public] Shown to users; default false';
COMMENT ON COLUMN notif.faq.sort_order IS '[Public] Display order; default 0';

CREATE TABLE notif.support_ticket (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  requester_app_user_id    bigint       NOT NULL,
  assignee_app_user_id     bigint,
  ticket_category_code     d_code       NOT NULL,
  ticket_status_code       d_code       NOT NULL DEFAULT 'open',
  ticket_subject           varchar(200) NOT NULL,
  opened_at                timestamptz  NOT NULL DEFAULT now(),
  resolved_at              timestamptz,
  created_at               timestamptz  NOT NULL DEFAULT now(),
  created_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz  NOT NULL DEFAULT now(),
  updated_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_support_ticket PRIMARY KEY (id),
  CONSTRAINT fk_support_ticket_requester_app_user_id FOREIGN KEY (requester_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_support_ticket_assignee_app_user_id FOREIGN KEY (assignee_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_support_ticket_ticket_category_code FOREIGN KEY (ticket_category_code) REFERENCES ref.ticket_category (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_support_ticket_ticket_status_code FOREIGN KEY (ticket_status_code) REFERENCES ref.ticket_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_support_ticket_resolved CHECK ((ticket_status_code IN ('resolved', 'closed')) = (resolved_at IS NOT NULL)),
  CONSTRAINT ck_support_ticket_time_range CHECK (resolved_at IS NULL OR resolved_at >= opened_at)
);
CREATE INDEX idx_support_ticket_requester_app_user_id ON notif.support_ticket (requester_app_user_id);
CREATE INDEX idx_support_ticket_open_queue ON notif.support_ticket (assignee_app_user_id, opened_at) WHERE ticket_status_code IN ('open', 'in_progress');
COMMENT ON TABLE  notif.support_ticket IS '[hard-delete] Support ticket raised by a user. Retention: 2 years after resolution';
COMMENT ON COLUMN notif.support_ticket.requester_app_user_id IS '[Internal] User who raised it';
COMMENT ON COLUMN notif.support_ticket.assignee_app_user_id IS '[Internal] Support agent; null: not yet assigned';
COMMENT ON COLUMN notif.support_ticket.ticket_category_code IS '[Internal] Category';
COMMENT ON COLUMN notif.support_ticket.ticket_status_code IS '[Internal] open, in_progress, resolved, closed; default open';
COMMENT ON COLUMN notif.support_ticket.ticket_subject IS '[Personal] Subject line, max 200';
COMMENT ON COLUMN notif.support_ticket.opened_at IS '[Internal] When raised (UTC)';
COMMENT ON COLUMN notif.support_ticket.resolved_at IS '[Internal] When resolved (UTC); null: still open';

CREATE TABLE notif.support_ticket_message (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  support_ticket_id         bigint        NOT NULL,
  author_app_user_id        bigint        NOT NULL,
  message_body              varchar(4000) NOT NULL,
  message_body_language_id  bigint,
  posted_at                 timestamptz   NOT NULL DEFAULT now(),
  created_at                timestamptz   NOT NULL DEFAULT now(),
  created_by                bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz   NOT NULL DEFAULT now(),
  updated_by                bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_support_ticket_message PRIMARY KEY (id),
  CONSTRAINT fk_support_ticket_message_support_ticket_id FOREIGN KEY (support_ticket_id) REFERENCES notif.support_ticket (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_support_ticket_message_author_app_user_id FOREIGN KEY (author_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_support_ticket_message_message_body_language_id FOREIGN KEY (message_body_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_support_ticket_message_support_ticket_id ON notif.support_ticket_message (support_ticket_id, posted_at);
CREATE INDEX idx_support_ticket_message_author_app_user_id ON notif.support_ticket_message (author_app_user_id);
COMMENT ON TABLE  notif.support_ticket_message IS '[hard-delete] Message in a support ticket thread (owned by the ticket; purged with it; never edited by the application)';
COMMENT ON COLUMN notif.support_ticket_message.support_ticket_id IS '[Internal] Ticket';
COMMENT ON COLUMN notif.support_ticket_message.author_app_user_id IS '[Internal] Requester or agent';
COMMENT ON COLUMN notif.support_ticket_message.message_body IS '[Personal] Message text, max 4000';
COMMENT ON COLUMN notif.support_ticket_message.message_body_language_id IS '[Internal] Language of message_body; null: not detected (RG7)';
COMMENT ON COLUMN notif.support_ticket_message.posted_at IS '[Internal] When posted (UTC)';
