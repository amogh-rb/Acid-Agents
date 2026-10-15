-- Master data (ref). Owner A.
--   M3: status lookups for the stubs.
--   M4: geography, currency, skills, education, industry, roles, identifier types and every enumeration lookup,
--       with PKs and FKs (columns + references); M6 adds unique / check constraints and indexes.
-- Names of people and places are stored in their original form (proper nouns). Translatable master data
-- (categories, industries, functions, roles, qualifications, fields) carries a label_key into ref.ui_translation.

SET app.current_user_id = '1';   -- system actor (admin.app_user id 1, created in ddl/15_stubs.sql)

-- =====================================================================================================
-- Enumeration lookups (ref.create_lookup: code, label_key, is_active, sort_order, audit columns)
-- =====================================================================================================

SELECT ref.create_lookup('ref.user_status', 'app_user account status');
SELECT ref.add_lookup_value('ref.user_status', 'pending_verification', 'Pending verification', 1);
SELECT ref.add_lookup_value('ref.user_status', 'active',               'Active',               2);
SELECT ref.add_lookup_value('ref.user_status', 'suspended',            'Suspended',            3);
SELECT ref.add_lookup_value('ref.user_status', 'deactivated',          'Deactivated',          4);

SELECT ref.create_lookup('ref.organisation_status', 'organisation account status');
SELECT ref.add_lookup_value('ref.organisation_status', 'pending_verification', 'Pending verification', 1);
SELECT ref.add_lookup_value('ref.organisation_status', 'active',               'Active',               2);
SELECT ref.add_lookup_value('ref.organisation_status', 'suspended',            'Suspended',            3);
SELECT ref.add_lookup_value('ref.organisation_status', 'closed',               'Closed',               4);

SELECT ref.create_lookup('ref.verification_status', 'outcome of an external verification (identity, company, tax)');
SELECT ref.add_lookup_value('ref.verification_status', 'pending',  'Pending',  1);
SELECT ref.add_lookup_value('ref.verification_status', 'verified', 'Verified', 2);
SELECT ref.add_lookup_value('ref.verification_status', 'failed',   'Failed',   3);
SELECT ref.add_lookup_value('ref.verification_status', 'expired',  'Expired',  4);

SELECT ref.create_lookup('ref.employment_type', 'employment type of a job or a past role');
SELECT ref.add_lookup_value('ref.employment_type', 'permanent',  'Permanent',  1);
SELECT ref.add_lookup_value('ref.employment_type', 'contract',   'Contract',   2);
SELECT ref.add_lookup_value('ref.employment_type', 'temporary',  'Temporary',  3);
SELECT ref.add_lookup_value('ref.employment_type', 'apprentice', 'Apprentice', 4);
SELECT ref.add_lookup_value('ref.employment_type', 'internship', 'Internship', 5);
SELECT ref.add_lookup_value('ref.employment_type', 'freelance',  'Freelance',  6);

SELECT ref.create_lookup('ref.work_type', 'where the work happens');
SELECT ref.add_lookup_value('ref.work_type', 'onsite', 'On-site', 1);
SELECT ref.add_lookup_value('ref.work_type', 'remote', 'Remote',  2);
SELECT ref.add_lookup_value('ref.work_type', 'hybrid', 'Hybrid',  3);

SELECT ref.create_lookup('ref.job_category', 'business category of a job requirement (docket Section 2)');
SELECT ref.add_lookup_value('ref.job_category', 'gig',                    'Gig and project work',          1);
SELECT ref.add_lookup_value('ref.job_category', 'general_staffing',       'General staffing',              2);
SELECT ref.add_lookup_value('ref.job_category', 'professional_staffing',  'Professional staffing',         3);
SELECT ref.add_lookup_value('ref.job_category', 'permanent',              'Permanent full-time',           4);
SELECT ref.add_lookup_value('ref.job_category', 'apprentice',             'Apprentice hiring',             5);
SELECT ref.add_lookup_value('ref.job_category', 'campus',                 'Campus and fresher hiring',     6);
SELECT ref.add_lookup_value('ref.job_category', 'consultant_marketplace', 'Consultant marketplace',        7);
SELECT ref.add_lookup_value('ref.job_category', 'managed_remote',         'Managed remote workforce',      8);

SELECT ref.create_lookup('ref.disclosure', 'unknown vs not applicable for amounts (RG5): disclosed, not_disclosed, not_applicable');
SELECT ref.add_lookup_value('ref.disclosure', 'disclosed',      'Disclosed',      1);
SELECT ref.add_lookup_value('ref.disclosure', 'not_disclosed',  'Not disclosed',  2);
SELECT ref.add_lookup_value('ref.disclosure', 'not_applicable', 'Not applicable', 3);

SELECT ref.create_lookup('ref.pay_period', 'period a salary, CTC or rate is quoted in');
ALTER TABLE ref.pay_period ADD COLUMN annual_multiplier numeric(8,2) NOT NULL DEFAULT 1;
COMMENT ON COLUMN ref.pay_period.annual_multiplier IS '[Public] Factor that annualises an amount for comparison (monthly 12, hourly 2080); default 1';
SELECT ref.add_lookup_value('ref.pay_period', 'annual',  'Per year',  1);
SELECT ref.add_lookup_value('ref.pay_period', 'monthly', 'Per month', 2);
SELECT ref.add_lookup_value('ref.pay_period', 'daily',   'Per day',   3);
SELECT ref.add_lookup_value('ref.pay_period', 'hourly',  'Per hour',  4);
UPDATE ref.pay_period SET annual_multiplier = CASE code WHEN 'monthly' THEN 12 WHEN 'daily' THEN 260 WHEN 'hourly' THEN 2080 ELSE 1 END;

SELECT ref.create_lookup('ref.notice_period', 'notice period a candidate must serve');
ALTER TABLE ref.notice_period ADD COLUMN notice_days smallint;
COMMENT ON COLUMN ref.notice_period.notice_days IS '[Public] Days of notice; null: open-ended (currently serving notice, end date varies)';
SELECT ref.add_lookup_value('ref.notice_period', 'immediate',      'Immediate',        1);
SELECT ref.add_lookup_value('ref.notice_period', 'days_15',        '15 days',          2);
SELECT ref.add_lookup_value('ref.notice_period', 'days_30',        '30 days',          3);
SELECT ref.add_lookup_value('ref.notice_period', 'days_60',        '60 days',          4);
SELECT ref.add_lookup_value('ref.notice_period', 'days_90',        '90 days',          5);
SELECT ref.add_lookup_value('ref.notice_period', 'serving_notice', 'Serving notice',   6);
UPDATE ref.notice_period SET notice_days = CASE code WHEN 'immediate' THEN 0 WHEN 'days_15' THEN 15 WHEN 'days_30' THEN 30
                                                     WHEN 'days_60' THEN 60 WHEN 'days_90' THEN 90 END;

SELECT ref.create_lookup('ref.proficiency_level', 'proficiency in a skill or language');
ALTER TABLE ref.proficiency_level ADD COLUMN level_rank smallint NOT NULL DEFAULT 1;
COMMENT ON COLUMN ref.proficiency_level.level_rank IS '[Public] Ordinal used for "at least" filters; default 1';
SELECT ref.add_lookup_value('ref.proficiency_level', 'beginner',     'Beginner',     1);
SELECT ref.add_lookup_value('ref.proficiency_level', 'intermediate', 'Intermediate', 2);
SELECT ref.add_lookup_value('ref.proficiency_level', 'advanced',     'Advanced',     3);
SELECT ref.add_lookup_value('ref.proficiency_level', 'expert',       'Expert',       4);
UPDATE ref.proficiency_level SET level_rank = sort_order;

SELECT ref.create_lookup('ref.gender', 'self-described gender');
SELECT ref.add_lookup_value('ref.gender', 'female',            'Female',            1);
SELECT ref.add_lookup_value('ref.gender', 'male',              'Male',              2);
SELECT ref.add_lookup_value('ref.gender', 'non_binary',        'Non-binary',        3);
SELECT ref.add_lookup_value('ref.gender', 'prefer_not_to_say', 'Prefer not to say', 4);

SELECT ref.create_lookup('ref.contact_type', 'kind of contact point');
SELECT ref.add_lookup_value('ref.contact_type', 'email',    'Email',    1);
SELECT ref.add_lookup_value('ref.contact_type', 'phone',    'Phone',    2);
SELECT ref.add_lookup_value('ref.contact_type', 'whatsapp', 'WhatsApp', 3);

SELECT ref.create_lookup('ref.address_type', 'purpose of an address');
SELECT ref.add_lookup_value('ref.address_type', 'current',        'Current',        1);
SELECT ref.add_lookup_value('ref.address_type', 'permanent',      'Permanent',      2);
SELECT ref.add_lookup_value('ref.address_type', 'correspondence', 'Correspondence', 3);

SELECT ref.create_lookup('ref.study_mode', 'mode of study');
SELECT ref.add_lookup_value('ref.study_mode', 'full_time', 'Full time', 1);
SELECT ref.add_lookup_value('ref.study_mode', 'part_time', 'Part time', 2);
SELECT ref.add_lookup_value('ref.study_mode', 'distance',  'Distance',  3);
SELECT ref.add_lookup_value('ref.study_mode', 'online',    'Online',    4);

SELECT ref.create_lookup('ref.project_kind', 'context a profile project was done in');
SELECT ref.add_lookup_value('ref.project_kind', 'employment', 'Employment', 1);
SELECT ref.add_lookup_value('ref.project_kind', 'academic',   'Academic',   2);
SELECT ref.add_lookup_value('ref.project_kind', 'personal',   'Personal',   3);
SELECT ref.add_lookup_value('ref.project_kind', 'gig',        'Gig',        4);

SELECT ref.create_lookup('ref.web_link_type', 'kind of external profile link');
SELECT ref.add_lookup_value('ref.web_link_type', 'linkedin',  'LinkedIn',  1);
SELECT ref.add_lookup_value('ref.web_link_type', 'github',    'GitHub',    2);
SELECT ref.add_lookup_value('ref.web_link_type', 'portfolio', 'Portfolio', 3);
SELECT ref.add_lookup_value('ref.web_link_type', 'other',     'Other',     4);

SELECT ref.create_lookup('ref.assessment_type', 'kind of assessment');
SELECT ref.add_lookup_value('ref.assessment_type', 'self_assessment', 'Self assessment', 1);
SELECT ref.add_lookup_value('ref.assessment_type', 'skill_test',      'Skill test',      2);
SELECT ref.add_lookup_value('ref.assessment_type', 'aptitude',        'Aptitude',        3);
SELECT ref.add_lookup_value('ref.assessment_type', 'language',        'Language',        4);

SELECT ref.create_lookup('ref.enrolment_status', 'state of a course enrolment');
SELECT ref.add_lookup_value('ref.enrolment_status', 'enrolled',    'Enrolled',    1);
SELECT ref.add_lookup_value('ref.enrolment_status', 'in_progress', 'In progress', 2);
SELECT ref.add_lookup_value('ref.enrolment_status', 'completed',   'Completed',   3);
SELECT ref.add_lookup_value('ref.enrolment_status', 'dropped',     'Dropped',     4);

SELECT ref.create_lookup('ref.referral_status', 'progress of a referral');
SELECT ref.add_lookup_value('ref.referral_status', 'invited',    'Invited',    1);
SELECT ref.add_lookup_value('ref.referral_status', 'registered', 'Registered', 2);
SELECT ref.add_lookup_value('ref.referral_status', 'applied',    'Applied',    3);
SELECT ref.add_lookup_value('ref.referral_status', 'hired',      'Hired',      4);
SELECT ref.add_lookup_value('ref.referral_status', 'expired',    'Expired',    5);

SELECT ref.create_lookup('ref.activity_event_type', 'candidate activity log event');
SELECT ref.add_lookup_value('ref.activity_event_type', 'login',           'Login',           1);
SELECT ref.add_lookup_value('ref.activity_event_type', 'profile_update',  'Profile update',  2);
SELECT ref.add_lookup_value('ref.activity_event_type', 'resume_upload',   'Resume upload',   3);
SELECT ref.add_lookup_value('ref.activity_event_type', 'resume_download', 'Resume download', 4);
SELECT ref.add_lookup_value('ref.activity_event_type', 'job_apply',       'Job application', 5);
SELECT ref.add_lookup_value('ref.activity_event_type', 'password_change', 'Password change', 6);

SELECT ref.create_lookup('ref.bookmark_action', 'bookmark history action');
SELECT ref.add_lookup_value('ref.bookmark_action', 'added',   'Added',   1);
SELECT ref.add_lookup_value('ref.bookmark_action', 'removed', 'Removed', 2);

SELECT ref.create_lookup('ref.job_requirement_status', 'job requirement lifecycle');
ALTER TABLE ref.job_requirement_status ADD COLUMN accepts_applications boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN ref.job_requirement_status.accepts_applications IS '[Public] true when new applications are allowed in this status; default false';
SELECT ref.add_lookup_value('ref.job_requirement_status', 'draft',     'Draft',     1);
SELECT ref.add_lookup_value('ref.job_requirement_status', 'open',      'Open',      2);
SELECT ref.add_lookup_value('ref.job_requirement_status', 'on_hold',   'On hold',   3);
SELECT ref.add_lookup_value('ref.job_requirement_status', 'closed',    'Closed',    4);
SELECT ref.add_lookup_value('ref.job_requirement_status', 'filled',    'Filled',    5);
SELECT ref.add_lookup_value('ref.job_requirement_status', 'cancelled', 'Cancelled', 6);
UPDATE ref.job_requirement_status SET accepts_applications = (code = 'open');

SELECT ref.create_lookup('ref.publish_state', 'visibility of a job requirement');
SELECT ref.add_lookup_value('ref.publish_state', 'unpublished', 'Unpublished', 1);
SELECT ref.add_lookup_value('ref.publish_state', 'scheduled',   'Scheduled',   2);
SELECT ref.add_lookup_value('ref.publish_state', 'published',   'Published',   3);
SELECT ref.add_lookup_value('ref.publish_state', 'expired',     'Expired',     4);
SELECT ref.add_lookup_value('ref.publish_state', 'withdrawn',   'Withdrawn',   5);

SELECT ref.create_lookup('ref.application_status', 'application pipeline status');
ALTER TABLE ref.application_status ADD COLUMN is_terminal boolean NOT NULL DEFAULT false;
ALTER TABLE ref.application_status ADD COLUMN pipeline_rank smallint NOT NULL DEFAULT 1;
COMMENT ON COLUMN ref.application_status.is_terminal IS '[Public] true when no further transition is allowed; default false';
COMMENT ON COLUMN ref.application_status.pipeline_rank IS '[Public] Funnel stage order for analytics; default 1';
SELECT ref.add_lookup_value('ref.application_status', 'applied',     'Applied',     1);
SELECT ref.add_lookup_value('ref.application_status', 'shortlisted', 'Shortlisted', 2);
SELECT ref.add_lookup_value('ref.application_status', 'interviewed', 'Interviewed', 3);
SELECT ref.add_lookup_value('ref.application_status', 'offered',     'Offered',     4);
SELECT ref.add_lookup_value('ref.application_status', 'joined',      'Joined',      5);
SELECT ref.add_lookup_value('ref.application_status', 'rejected',    'Rejected',    6);
SELECT ref.add_lookup_value('ref.application_status', 'withdrawn',   'Withdrawn',   7);
UPDATE ref.application_status
   SET is_terminal = code IN ('joined', 'rejected', 'withdrawn'),
       pipeline_rank = CASE code WHEN 'applied' THEN 1 WHEN 'shortlisted' THEN 2 WHEN 'interviewed' THEN 3
                                 WHEN 'offered' THEN 4 WHEN 'joined' THEN 5 ELSE 9 END;

SELECT ref.create_lookup('ref.application_source', 'how an application reached the pipeline');
SELECT ref.add_lookup_value('ref.application_source', 'direct',     'Direct',     1);
SELECT ref.add_lookup_value('ref.application_source', 'sourced',    'Sourced',    2);
SELECT ref.add_lookup_value('ref.application_source', 'referral',   'Referral',   3);
SELECT ref.add_lookup_value('ref.application_source', 'campus',     'Campus',     4);
SELECT ref.add_lookup_value('ref.application_source', 'consultant', 'Consultant', 5);
SELECT ref.add_lookup_value('ref.application_source', 'imported',   'Imported',   6);

SELECT ref.create_lookup('ref.rejection_reason', 'why an application was rejected');
SELECT ref.add_lookup_value('ref.rejection_reason', 'skills_mismatch',     'Skills mismatch',     1);
SELECT ref.add_lookup_value('ref.rejection_reason', 'experience_mismatch', 'Experience mismatch', 2);
SELECT ref.add_lookup_value('ref.rejection_reason', 'salary_mismatch',     'Salary mismatch',     3);
SELECT ref.add_lookup_value('ref.rejection_reason', 'location_mismatch',   'Location mismatch',   4);
SELECT ref.add_lookup_value('ref.rejection_reason', 'failed_interview',    'Failed interview',    5);
SELECT ref.add_lookup_value('ref.rejection_reason', 'offer_declined',      'Offer declined',      6);
SELECT ref.add_lookup_value('ref.rejection_reason', 'no_show',             'No show',             7);
SELECT ref.add_lookup_value('ref.rejection_reason', 'position_filled',     'Position filled',     8);
SELECT ref.add_lookup_value('ref.rejection_reason', 'other',               'Other',               9);

SELECT ref.create_lookup('ref.question_type', 'answer format of a screening question');
SELECT ref.add_lookup_value('ref.question_type', 'single_choice', 'Single choice', 1);
SELECT ref.add_lookup_value('ref.question_type', 'multi_choice',  'Multiple choice', 2);
SELECT ref.add_lookup_value('ref.question_type', 'short_text',    'Short text',    3);
SELECT ref.add_lookup_value('ref.question_type', 'numeric',       'Number',        4);
SELECT ref.add_lookup_value('ref.question_type', 'yes_no',        'Yes / No',      5);

SELECT ref.create_lookup('ref.interview_mode', 'how an interview is held');
SELECT ref.add_lookup_value('ref.interview_mode', 'in_person', 'In person', 1);
SELECT ref.add_lookup_value('ref.interview_mode', 'video',     'Video',     2);
SELECT ref.add_lookup_value('ref.interview_mode', 'phone',     'Phone',     3);

SELECT ref.create_lookup('ref.interview_status', 'scheduling state of an interview');
SELECT ref.add_lookup_value('ref.interview_status', 'scheduled',   'Scheduled',   1);
SELECT ref.add_lookup_value('ref.interview_status', 'completed',   'Completed',   2);
SELECT ref.add_lookup_value('ref.interview_status', 'cancelled',   'Cancelled',   3);
SELECT ref.add_lookup_value('ref.interview_status', 'no_show',     'No show',     4);
SELECT ref.add_lookup_value('ref.interview_status', 'rescheduled', 'Rescheduled', 5);

SELECT ref.create_lookup('ref.interview_outcome', 'result of a completed interview');
SELECT ref.add_lookup_value('ref.interview_outcome', 'passed',  'Passed',  1);
SELECT ref.add_lookup_value('ref.interview_outcome', 'failed',  'Failed',  2);
SELECT ref.add_lookup_value('ref.interview_outcome', 'on_hold', 'On hold', 3);

SELECT ref.create_lookup('ref.offer_status', 'state of an offer');
SELECT ref.add_lookup_value('ref.offer_status', 'extended',  'Extended',  1);
SELECT ref.add_lookup_value('ref.offer_status', 'accepted',  'Accepted',  2);
SELECT ref.add_lookup_value('ref.offer_status', 'declined',  'Declined',  3);
SELECT ref.add_lookup_value('ref.offer_status', 'withdrawn', 'Withdrawn', 4);
SELECT ref.add_lookup_value('ref.offer_status', 'expired',   'Expired',   5);

SELECT ref.create_lookup('ref.joining_status', 'state of a joining');
SELECT ref.add_lookup_value('ref.joining_status', 'expected', 'Expected', 1);
SELECT ref.add_lookup_value('ref.joining_status', 'joined',   'Joined',   2);
SELECT ref.add_lookup_value('ref.joining_status', 'no_show',  'No show',  3);
SELECT ref.add_lookup_value('ref.joining_status', 'deferred', 'Deferred', 4);

SELECT ref.create_lookup('ref.qualification_level', 'level of a qualification');
ALTER TABLE ref.qualification_level ADD COLUMN level_rank smallint NOT NULL DEFAULT 1;
COMMENT ON COLUMN ref.qualification_level.level_rank IS '[Public] Ordinal for "minimum qualification" filters; default 1';
SELECT ref.add_lookup_value('ref.qualification_level', 'secondary',        'Secondary (10th)',         1);
SELECT ref.add_lookup_value('ref.qualification_level', 'higher_secondary', 'Higher secondary (12th)',  2);
SELECT ref.add_lookup_value('ref.qualification_level', 'certificate',      'Certificate / ITI',        3);
SELECT ref.add_lookup_value('ref.qualification_level', 'diploma',          'Diploma',                  4);
SELECT ref.add_lookup_value('ref.qualification_level', 'bachelor',         'Bachelor''s degree',       5);
SELECT ref.add_lookup_value('ref.qualification_level', 'master',           'Master''s degree',         6);
SELECT ref.add_lookup_value('ref.qualification_level', 'doctorate',        'Doctorate',                7);
UPDATE ref.qualification_level SET level_rank = sort_order;

-- =====================================================================================================
-- Geography and currency
-- =====================================================================================================

CREATE TABLE ref.currency (
  id            bigint GENERATED ALWAYS AS IDENTITY,
  code          d_currency_code NOT NULL,
  currency_name varchar(100)    NOT NULL,
  label_key     varchar(150)    NOT NULL,
  minor_unit    smallint        NOT NULL DEFAULT 2,
  symbol        varchar(8)      NOT NULL,
  is_active     boolean         NOT NULL DEFAULT true,
  sort_order    integer         NOT NULL DEFAULT 0,
  created_at    timestamptz     NOT NULL DEFAULT now(),
  created_by    bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at    timestamptz     NOT NULL DEFAULT now(),
  updated_by    bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_currency PRIMARY KEY (id),
  CONSTRAINT uq_currency_code UNIQUE (code),
  CONSTRAINT fk_currency_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.currency IS '[hard-delete] ISO 4217 currency; FK target of every money companion column';
COMMENT ON COLUMN ref.currency.code IS '[Public] ISO 4217 alphabetic code (INR, USD)';
COMMENT ON COLUMN ref.currency.currency_name IS '[Public] English name; translations via label_key';
COMMENT ON COLUMN ref.currency.label_key IS '[Public] UI label key for the currency name';
COMMENT ON COLUMN ref.currency.minor_unit IS '[Public] ISO 4217 decimal places; default 2 (d_money stores 2, see decision D12)';
COMMENT ON COLUMN ref.currency.symbol IS '[Public] Display symbol (₹, $)';
COMMENT ON COLUMN ref.currency.is_active IS '[Public] false hides the currency from new use; default true';
COMMENT ON COLUMN ref.currency.sort_order IS '[Public] Display order; default 0';

CREATE TABLE ref.timezone (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  iana_name   varchar(64)  NOT NULL,
  is_active   boolean      NOT NULL DEFAULT true,
  created_at  timestamptz  NOT NULL DEFAULT now(),
  created_by  bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at  timestamptz  NOT NULL DEFAULT now(),
  updated_by  bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_timezone PRIMARY KEY (id),
  CONSTRAINT uq_timezone_iana_name UNIQUE (iana_name)
);
COMMENT ON TABLE  ref.timezone IS '[hard-delete] IANA time zone used to display UTC timestamps in local time (RG3 Timestamp)';
COMMENT ON COLUMN ref.timezone.iana_name IS '[Public] IANA zone name (Asia/Kolkata); valid for AT TIME ZONE';
COMMENT ON COLUMN ref.timezone.is_active IS '[Public] false hides the zone from new use; default true';

CREATE TABLE ref.country (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  iso_alpha2             char(2)         NOT NULL,
  iso_alpha3             char(3)         NOT NULL,
  country_name           varchar(100)    NOT NULL,
  label_key              varchar(150)    NOT NULL,
  phone_prefix           varchar(5)      NOT NULL,
  default_currency_code  d_currency_code NOT NULL,
  is_active              boolean         NOT NULL DEFAULT true,
  sort_order             integer         NOT NULL DEFAULT 0,
  created_at             timestamptz     NOT NULL DEFAULT now(),
  created_by             bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz     NOT NULL DEFAULT now(),
  updated_by             bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_country PRIMARY KEY (id),
  CONSTRAINT uq_country_iso_alpha2 UNIQUE (iso_alpha2),
  CONSTRAINT fk_country_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_country_default_currency_code FOREIGN KEY (default_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.country IS '[hard-delete] ISO 3166-1 country';
COMMENT ON COLUMN ref.country.iso_alpha2 IS '[Public] ISO 3166-1 alpha-2 code (IN); natural key';
COMMENT ON COLUMN ref.country.iso_alpha3 IS '[Public] ISO 3166-1 alpha-3 code (IND)';
COMMENT ON COLUMN ref.country.country_name IS '[Public] English short name; translations via label_key';
COMMENT ON COLUMN ref.country.label_key IS '[Public] UI label key for the country name';
COMMENT ON COLUMN ref.country.phone_prefix IS '[Public] International dialling prefix (+91)';
COMMENT ON COLUMN ref.country.default_currency_code IS '[Public] Currency proposed for amounts entered in this country';
COMMENT ON COLUMN ref.country.is_active IS '[Public] false hides the country from new use; default true';
COMMENT ON COLUMN ref.country.sort_order IS '[Public] Display order; default 0';

CREATE TABLE ref.state (
  id              bigint GENERATED ALWAYS AS IDENTITY,
  country_id      bigint       NOT NULL,
  state_name      varchar(100) NOT NULL,
  iso_subdivision varchar(10)  NOT NULL,
  is_active       boolean      NOT NULL DEFAULT true,
  created_at      timestamptz  NOT NULL DEFAULT now(),
  created_by      bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at      timestamptz  NOT NULL DEFAULT now(),
  updated_by      bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_state PRIMARY KEY (id),
  CONSTRAINT uq_state_country_id_id UNIQUE (country_id, id),
  CONSTRAINT fk_state_country_id FOREIGN KEY (country_id) REFERENCES ref.country (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.state IS '[hard-delete] First-level subdivision (state, province) of a country';
COMMENT ON COLUMN ref.state.country_id IS '[Public] Country the subdivision belongs to';
COMMENT ON COLUMN ref.state.state_name IS '[Public] Name in its official romanised form';
COMMENT ON COLUMN ref.state.iso_subdivision IS '[Public] ISO 3166-2 code (IN-TN)';
COMMENT ON COLUMN ref.state.is_active IS '[Public] false hides the subdivision from new use; default true';

CREATE TABLE ref.city (
  id           bigint GENERATED ALWAYS AS IDENTITY,
  country_id   bigint       NOT NULL,
  state_id     bigint,
  city_name    varchar(100) NOT NULL,
  timezone_id  bigint,
  latitude     d_lat,
  longitude    d_lng,
  geonames_id  bigint,
  is_active    boolean      NOT NULL DEFAULT true,
  created_at   timestamptz  NOT NULL DEFAULT now(),
  created_by   bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at   timestamptz  NOT NULL DEFAULT now(),
  updated_by   bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_city PRIMARY KEY (id),
  CONSTRAINT fk_city_country_id FOREIGN KEY (country_id) REFERENCES ref.country (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_city_country_id_state_id FOREIGN KEY (country_id, state_id) REFERENCES ref.state (country_id, id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_city_timezone_id FOREIGN KEY (timezone_id) REFERENCES ref.timezone (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.city IS '[hard-delete] City or town; job locations, addresses and preferred locations';
COMMENT ON COLUMN ref.city.country_id IS '[Public] Country (kept even with a state so stateless countries work)';
COMMENT ON COLUMN ref.city.state_id IS '[Public] Subdivision; null: country has no first-level subdivision (Singapore). Composite FK keeps it in the same country';
COMMENT ON COLUMN ref.city.city_name IS '[Public] Name in its official romanised form';
COMMENT ON COLUMN ref.city.timezone_id IS '[Public] Local time zone for display; null: not mapped yet, the country default is used';
COMMENT ON COLUMN ref.city.latitude IS '[Public] City centre, WGS84, 6 dp, source GeoNames; null: not geocoded yet';
COMMENT ON COLUMN ref.city.longitude IS '[Public] City centre, WGS84, 6 dp, source GeoNames; null: not geocoded yet';
COMMENT ON COLUMN ref.city.geonames_id IS '[Public] GeoNames identifier of the source record; nofk: external reference (mapping boundary); null: city added manually';
COMMENT ON COLUMN ref.city.is_active IS '[Public] false hides the city from new use; default true';

-- =====================================================================================================
-- Skills, education, industry, roles
-- =====================================================================================================

CREATE TABLE ref.skill_category (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  category_name             varchar(100) NOT NULL,
  parent_skill_category_id  bigint,
  label_key                 varchar(150) NOT NULL,
  is_active                 boolean      NOT NULL DEFAULT true,
  sort_order                integer      NOT NULL DEFAULT 0,
  created_at                timestamptz  NOT NULL DEFAULT now(),
  created_by                bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz  NOT NULL DEFAULT now(),
  updated_by                bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_skill_category PRIMARY KEY (id),
  CONSTRAINT fk_skill_category_parent_skill_category_id FOREIGN KEY (parent_skill_category_id) REFERENCES ref.skill_category (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_skill_category_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.skill_category IS '[hard-delete] Hierarchical grouping of skills';
COMMENT ON COLUMN ref.skill_category.category_name IS '[Public] English name; translations via label_key';
COMMENT ON COLUMN ref.skill_category.parent_skill_category_id IS '[Public] Parent category; null: top-level category';
COMMENT ON COLUMN ref.skill_category.label_key IS '[Public] UI label key for the category name';
COMMENT ON COLUMN ref.skill_category.is_active IS '[Public] false hides the category from new use; default true';
COMMENT ON COLUMN ref.skill_category.sort_order IS '[Public] Display order; default 0';

CREATE TABLE ref.skill (
  id                 bigint GENERATED ALWAYS AS IDENTITY,
  skill_name         varchar(100) NOT NULL,
  skill_category_id  bigint       NOT NULL,
  is_active          boolean      NOT NULL DEFAULT true,
  created_at         timestamptz  NOT NULL DEFAULT now(),
  created_by         bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at         timestamptz  NOT NULL DEFAULT now(),
  updated_by         bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_skill PRIMARY KEY (id),
  CONSTRAINT fk_skill_skill_category_id FOREIGN KEY (skill_category_id) REFERENCES ref.skill_category (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.skill IS '[hard-delete] Canonical skill shared by profiles, jobs, assessments and courses (name is a proper noun, not translated)';
COMMENT ON COLUMN ref.skill.skill_name IS '[Public] Canonical skill name (PostgreSQL, Welding)';
COMMENT ON COLUMN ref.skill.skill_category_id IS '[Public] Category the skill belongs to';
COMMENT ON COLUMN ref.skill.is_active IS '[Public] false hides the skill from new use (merged duplicates); default true';

CREATE TABLE ref.qualification (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  qualification_name        varchar(150) NOT NULL,
  short_name                varchar(30)  NOT NULL,
  qualification_level_code  d_code       NOT NULL,
  label_key                 varchar(150) NOT NULL,
  is_active                 boolean      NOT NULL DEFAULT true,
  created_at                timestamptz  NOT NULL DEFAULT now(),
  created_by                bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz  NOT NULL DEFAULT now(),
  updated_by                bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_qualification PRIMARY KEY (id),
  CONSTRAINT fk_qualification_qualification_level_code FOREIGN KEY (qualification_level_code) REFERENCES ref.qualification_level (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_qualification_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.qualification IS '[hard-delete] Named qualification (B.Tech, ITI Fitter, MBA) at a level';
COMMENT ON COLUMN ref.qualification.qualification_name IS '[Public] Full English name; translations via label_key';
COMMENT ON COLUMN ref.qualification.short_name IS '[Public] Abbreviation shown in lists (B.Tech)';
COMMENT ON COLUMN ref.qualification.qualification_level_code IS '[Public] Level of the qualification';
COMMENT ON COLUMN ref.qualification.label_key IS '[Public] UI label key for the qualification name';
COMMENT ON COLUMN ref.qualification.is_active IS '[Public] false hides the qualification from new use; default true';

CREATE TABLE ref.field_of_study (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  field_name  varchar(150) NOT NULL,
  label_key   varchar(150) NOT NULL,
  is_active   boolean      NOT NULL DEFAULT true,
  created_at  timestamptz  NOT NULL DEFAULT now(),
  created_by  bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at  timestamptz  NOT NULL DEFAULT now(),
  updated_by  bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_field_of_study PRIMARY KEY (id),
  CONSTRAINT fk_field_of_study_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.field_of_study IS '[hard-delete] Specialisation (Computer Science, Mechanical)';
COMMENT ON COLUMN ref.field_of_study.field_name IS '[Public] English name; translations via label_key';
COMMENT ON COLUMN ref.field_of_study.label_key IS '[Public] UI label key for the field name';
COMMENT ON COLUMN ref.field_of_study.is_active IS '[Public] false hides the field from new use; default true';

CREATE TABLE ref.institution (
  id                 bigint GENERATED ALWAYS AS IDENTITY,
  institution_name   varchar(250) NOT NULL,
  country_id         bigint       NOT NULL,
  city_id            bigint,
  is_campus_partner  boolean      NOT NULL DEFAULT false,
  is_active          boolean      NOT NULL DEFAULT true,
  created_at         timestamptz  NOT NULL DEFAULT now(),
  created_by         bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at         timestamptz  NOT NULL DEFAULT now(),
  updated_by         bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_institution PRIMARY KEY (id),
  CONSTRAINT fk_institution_country_id FOREIGN KEY (country_id) REFERENCES ref.country (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_institution_city_id FOREIGN KEY (city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.institution IS '[hard-delete] School, college or university (education records, campus hiring)';
COMMENT ON COLUMN ref.institution.institution_name IS '[Public] Official name (proper noun, not translated)';
COMMENT ON COLUMN ref.institution.country_id IS '[Public] Country of the institution';
COMMENT ON COLUMN ref.institution.city_id IS '[Public] Campus city; null: open or distance university without a campus city';
COMMENT ON COLUMN ref.institution.is_campus_partner IS '[Internal] true when a placement officer (TPO) runs campus drives with us; default false';
COMMENT ON COLUMN ref.institution.is_active IS '[Public] false hides the institution from new use; default true';

CREATE TABLE ref.industry (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  industry_name       varchar(150) NOT NULL,
  parent_industry_id  bigint,
  label_key           varchar(150) NOT NULL,
  is_active           boolean      NOT NULL DEFAULT true,
  sort_order          integer      NOT NULL DEFAULT 0,
  created_at          timestamptz  NOT NULL DEFAULT now(),
  created_by          bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at          timestamptz  NOT NULL DEFAULT now(),
  updated_by          bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_industry PRIMARY KEY (id),
  CONSTRAINT fk_industry_parent_industry_id FOREIGN KEY (parent_industry_id) REFERENCES ref.industry (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_industry_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.industry IS '[hard-delete] Hierarchical industry classification';
COMMENT ON COLUMN ref.industry.industry_name IS '[Public] English name; translations via label_key';
COMMENT ON COLUMN ref.industry.parent_industry_id IS '[Public] Parent industry; null: top-level industry';
COMMENT ON COLUMN ref.industry.label_key IS '[Public] UI label key for the industry name';
COMMENT ON COLUMN ref.industry.is_active IS '[Public] false hides the industry from new use; default true';
COMMENT ON COLUMN ref.industry.sort_order IS '[Public] Display order; default 0';

CREATE TABLE ref.job_function (
  id             bigint GENERATED ALWAYS AS IDENTITY,
  function_name  varchar(100) NOT NULL,
  label_key      varchar(150) NOT NULL,
  is_active      boolean      NOT NULL DEFAULT true,
  sort_order     integer      NOT NULL DEFAULT 0,
  created_at     timestamptz  NOT NULL DEFAULT now(),
  created_by     bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at     timestamptz  NOT NULL DEFAULT now(),
  updated_by     bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_function PRIMARY KEY (id),
  CONSTRAINT fk_job_function_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.job_function IS '[hard-delete] Department or function (Engineering, Sales, Operations)';
COMMENT ON COLUMN ref.job_function.function_name IS '[Public] English name; translations via label_key';
COMMENT ON COLUMN ref.job_function.label_key IS '[Public] UI label key for the function name';
COMMENT ON COLUMN ref.job_function.is_active IS '[Public] false hides the function from new use; default true';
COMMENT ON COLUMN ref.job_function.sort_order IS '[Public] Display order; default 0';

CREATE TABLE ref.job_role (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  role_name        varchar(150) NOT NULL,
  job_function_id  bigint       NOT NULL,
  label_key        varchar(150) NOT NULL,
  is_active        boolean      NOT NULL DEFAULT true,
  created_at       timestamptz  NOT NULL DEFAULT now(),
  created_by       bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at       timestamptz  NOT NULL DEFAULT now(),
  updated_by       bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_role PRIMARY KEY (id),
  CONSTRAINT fk_job_role_job_function_id FOREIGN KEY (job_function_id) REFERENCES ref.job_function (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_role_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  ref.job_role IS '[hard-delete] Standard role within a function (Backend Developer, Forklift Operator)';
COMMENT ON COLUMN ref.job_role.role_name IS '[Public] English name; translations via label_key';
COMMENT ON COLUMN ref.job_role.job_function_id IS '[Public] Function the role belongs to';
COMMENT ON COLUMN ref.job_role.label_key IS '[Public] UI label key for the role name';
COMMENT ON COLUMN ref.job_role.is_active IS '[Public] false hides the role from new use; default true';

-- identifier_type: a lookup with validation metadata (shared by Profile and Organisation)
SELECT ref.create_lookup('ref.identifier_type', 'national and tax identifier types with validation rules');
ALTER TABLE ref.identifier_type
  ADD COLUMN validation_regex        varchar(200),
  ADD COLUMN applies_to_person       boolean NOT NULL DEFAULT false,
  ADD COLUMN applies_to_organisation boolean NOT NULL DEFAULT false,
  ADD COLUMN country_id              bigint,
  ADD CONSTRAINT fk_identifier_type_country_id FOREIGN KEY (country_id) REFERENCES ref.country (id) ON UPDATE NO ACTION ON DELETE RESTRICT;
COMMENT ON COLUMN ref.identifier_type.validation_regex IS '[Public] Format rule applied by the verification flow before tokenising; null: format varies by issuer (passport), checked by the external service';
COMMENT ON COLUMN ref.identifier_type.applies_to_person IS '[Public] true when candidates may hold this identifier; default false';
COMMENT ON COLUMN ref.identifier_type.applies_to_organisation IS '[Public] true when organisations may hold this identifier; default false';
COMMENT ON COLUMN ref.identifier_type.country_id IS '[Public] Issuing country; null: not country-specific (passport)';

-- =====================================================================================================
-- Seed rows (minimal reference set; the M19 generator adds volume)
-- =====================================================================================================

INSERT INTO ref.currency (code, currency_name, label_key, minor_unit, symbol, sort_order) VALUES
  ('INR', 'Indian Rupee',       ref.label_for('currency', 'Indian Rupee'),       2, '₹',   1),
  ('USD', 'US Dollar',          ref.label_for('currency', 'US Dollar'),          2, '$',   2),
  ('EUR', 'Euro',               ref.label_for('currency', 'Euro'),               2, '€',   3),
  ('GBP', 'Pound Sterling',     ref.label_for('currency', 'Pound Sterling'),     2, '£',   4),
  ('AED', 'UAE Dirham',         ref.label_for('currency', 'UAE Dirham'),         2, 'AED', 5),
  ('SGD', 'Singapore Dollar',   ref.label_for('currency', 'Singapore Dollar'),   2, 'S$',  6);

INSERT INTO ref.timezone (iana_name) VALUES
  ('Asia/Kolkata'), ('Asia/Dubai'), ('Asia/Singapore'), ('Europe/London'), ('Europe/Berlin'),
  ('America/New_York'), ('America/Los_Angeles'), ('UTC');

INSERT INTO ref.country (iso_alpha2, iso_alpha3, country_name, label_key, phone_prefix, default_currency_code, sort_order) VALUES
  ('IN', 'IND', 'India',                ref.label_for('country', 'India'),                '+91',  'INR', 1),
  ('US', 'USA', 'United States',        ref.label_for('country', 'United States'),        '+1',   'USD', 2),
  ('GB', 'GBR', 'United Kingdom',       ref.label_for('country', 'United Kingdom'),       '+44',  'GBP', 3),
  ('AE', 'ARE', 'United Arab Emirates', ref.label_for('country', 'United Arab Emirates'), '+971', 'AED', 4),
  ('SG', 'SGP', 'Singapore',            ref.label_for('country', 'Singapore'),            '+65',  'SGD', 5),
  ('DE', 'DEU', 'Germany',              ref.label_for('country', 'Germany'),              '+49',  'EUR', 6);

INSERT INTO ref.state (country_id, state_name, iso_subdivision)
SELECT c.id, v.state_name, v.iso
  FROM (VALUES ('IN', 'Tamil Nadu', 'IN-TN'), ('IN', 'Karnataka', 'IN-KA'), ('IN', 'Maharashtra', 'IN-MH'),
               ('IN', 'Delhi', 'IN-DL'), ('IN', 'Telangana', 'IN-TG'), ('IN', 'West Bengal', 'IN-WB'),
               ('US', 'California', 'US-CA'), ('US', 'New York', 'US-NY'), ('GB', 'England', 'GB-ENG'),
               ('AE', 'Dubai', 'AE-DU'), ('DE', 'Berlin', 'DE-BE')) v(iso2, state_name, iso)
  JOIN ref.country c ON c.iso_alpha2 = v.iso2;

INSERT INTO ref.city (country_id, state_id, city_name, timezone_id, latitude, longitude, geonames_id)
SELECT c.id, s.id, v.city_name, tz.id, v.lat, v.lng, v.geonames_id
  FROM (VALUES ('IN', 'IN-TN', 'Chennai',       'Asia/Kolkata',        13.082680,  80.270718, 1264527),
               ('IN', 'IN-TN', 'Coimbatore',    'Asia/Kolkata',        11.016844,  76.955832, 1273865),
               ('IN', 'IN-KA', 'Bengaluru',     'Asia/Kolkata',        12.971599,  77.594566, 1277333),
               ('IN', 'IN-MH', 'Mumbai',        'Asia/Kolkata',        19.076090,  72.877426, 1275339),
               ('IN', 'IN-MH', 'Pune',          'Asia/Kolkata',        18.520430,  73.856743, 1259229),
               ('IN', 'IN-DL', 'New Delhi',     'Asia/Kolkata',        28.613939,  77.209023, 1261481),
               ('IN', 'IN-TG', 'Hyderabad',     'Asia/Kolkata',        17.385044,  78.486671, 1269843),
               ('IN', 'IN-WB', 'Kolkata',       'Asia/Kolkata',        22.572646,  88.363895, 1275004),
               ('US', 'US-CA', 'San Francisco', 'America/Los_Angeles', 37.774929, -122.419416, 5391959),
               ('US', 'US-NY', 'New York',      'America/New_York',    40.712776,  -74.005974, 5128581),
               ('GB', 'GB-ENG', 'London',       'Europe/London',       51.507351,   -0.127758, 2643743),
               ('AE', 'AE-DU', 'Dubai',         'Asia/Dubai',          25.204849,   55.270783, 292223),
               ('SG', NULL,    'Singapore',     'Asia/Singapore',       1.352083,  103.819836, 1880252),
               ('DE', 'DE-BE', 'Berlin',        'Europe/Berlin',       52.520008,   13.404954, 2950159))
       v(iso2, iso_sub, city_name, tz_name, lat, lng, geonames_id)
  JOIN ref.country c ON c.iso_alpha2 = v.iso2
  LEFT JOIN ref.state s ON s.iso_subdivision = v.iso_sub
  JOIN ref.timezone tz ON tz.iana_name = v.tz_name;

INSERT INTO ref.skill_category (category_name, label_key, sort_order) VALUES
  ('Software Development', ref.label_for('skill_category', 'Software Development'), 1),
  ('Data and Analytics',   ref.label_for('skill_category', 'Data and Analytics'),   2),
  ('Trades and Technical', ref.label_for('skill_category', 'Trades and Technical'), 3),
  ('Business and Finance', ref.label_for('skill_category', 'Business and Finance'), 4),
  ('Languages and Communication', ref.label_for('skill_category', 'Languages and Communication'), 5);
INSERT INTO ref.skill_category (category_name, parent_skill_category_id, label_key, sort_order)
SELECT v.name, p.id, ref.label_for('skill_category', v.name), v.ord
  FROM (VALUES ('Backend Development', 'Software Development', 1), ('Frontend Development', 'Software Development', 2),
               ('Databases', 'Data and Analytics', 1)) v(name, parent, ord)
  JOIN ref.skill_category p ON p.category_name = v.parent;

INSERT INTO ref.skill (skill_name, skill_category_id)
SELECT v.skill_name, sc.id
  FROM (VALUES ('Java', 'Backend Development'), ('Python', 'Backend Development'), ('Go', 'Backend Development'),
               ('Node.js', 'Backend Development'), ('React', 'Frontend Development'), ('TypeScript', 'Frontend Development'),
               ('PostgreSQL', 'Databases'), ('MySQL', 'Databases'), ('SQL', 'Databases'), ('Power BI', 'Data and Analytics'),
               ('Machine Learning', 'Data and Analytics'), ('Welding', 'Trades and Technical'), ('Electrical Wiring', 'Trades and Technical'),
               ('Forklift Operation', 'Trades and Technical'), ('CNC Machining', 'Trades and Technical'), ('Tally', 'Business and Finance'),
               ('Accounting', 'Business and Finance'), ('Sales', 'Business and Finance'), ('Customer Service', 'Languages and Communication'),
               ('Business English', 'Languages and Communication')) v(skill_name, category)
  JOIN ref.skill_category sc ON sc.category_name = v.category;

INSERT INTO ref.qualification (qualification_name, short_name, qualification_level_code, label_key)
SELECT v.name, v.short_name, v.level, ref.label_for('qualification', v.name)
  FROM (VALUES ('Secondary School Certificate', 'SSC', 'secondary'), ('Higher Secondary Certificate', 'HSC', 'higher_secondary'),
               ('ITI Fitter', 'ITI', 'certificate'), ('Diploma in Engineering', 'Diploma', 'diploma'),
               ('Bachelor of Technology', 'B.Tech', 'bachelor'), ('Bachelor of Commerce', 'B.Com', 'bachelor'),
               ('Bachelor of Science', 'B.Sc', 'bachelor'), ('Master of Technology', 'M.Tech', 'master'),
               ('Master of Business Administration', 'MBA', 'master'), ('Doctor of Philosophy', 'PhD', 'doctorate')) v(name, short_name, level);

INSERT INTO ref.field_of_study (field_name, label_key)
SELECT v.name, ref.label_for('field_of_study', v.name)
  FROM (VALUES ('Computer Science'), ('Information Technology'), ('Mechanical Engineering'), ('Electrical Engineering'),
               ('Civil Engineering'), ('Commerce'), ('Finance'), ('Marketing'), ('Mathematics'), ('Physics')) v(name);

INSERT INTO ref.institution (institution_name, country_id, city_id, is_campus_partner)
SELECT v.name, ci.country_id, ci.id, v.partner
  FROM (VALUES ('Indian Institute of Technology Madras', 'Chennai', true), ('Anna University', 'Chennai', true),
               ('PSG College of Technology', 'Coimbatore', true), ('Indian Institute of Science', 'Bengaluru', false),
               ('University of Mumbai', 'Mumbai', false), ('University of Delhi', 'New Delhi', false)) v(name, city, partner)
  JOIN ref.city ci ON ci.city_name = v.city;
INSERT INTO ref.institution (institution_name, country_id)
SELECT 'Indira Gandhi National Open University', id FROM ref.country WHERE iso_alpha2 = 'IN';

INSERT INTO ref.industry (industry_name, label_key, sort_order)
SELECT v.name, ref.label_for('industry', v.name), v.ord
  FROM (VALUES ('Information Technology', 1), ('Manufacturing', 2), ('Banking and Financial Services', 3),
               ('Retail', 4), ('Healthcare', 5), ('Logistics', 6), ('Education', 7)) v(name, ord);
INSERT INTO ref.industry (industry_name, parent_industry_id, label_key, sort_order)
SELECT v.name, p.id, ref.label_for('industry', v.name), v.ord
  FROM (VALUES ('Software Products', 'Information Technology', 1), ('IT Services', 'Information Technology', 2),
               ('Automotive', 'Manufacturing', 1)) v(name, parent, ord)
  JOIN ref.industry p ON p.industry_name = v.parent;

INSERT INTO ref.job_function (function_name, label_key, sort_order)
SELECT v.name, ref.label_for('job_function', v.name), v.ord
  FROM (VALUES ('Engineering', 1), ('Data', 2), ('Operations', 3), ('Sales', 4), ('Finance', 5),
               ('Human Resources', 6), ('Customer Support', 7)) v(name, ord);

INSERT INTO ref.job_role (role_name, job_function_id, label_key)
SELECT v.name, f.id, ref.label_for('job_role', v.name)
  FROM (VALUES ('Backend Developer', 'Engineering'), ('Frontend Developer', 'Engineering'), ('Database Administrator', 'Engineering'),
               ('Data Analyst', 'Data'), ('Data Engineer', 'Data'), ('Forklift Operator', 'Operations'), ('Welder', 'Operations'),
               ('Warehouse Associate', 'Operations'), ('Sales Executive', 'Sales'), ('Accountant', 'Finance'),
               ('Recruiter', 'Human Resources'), ('Customer Support Associate', 'Customer Support')) v(name, fn)
  JOIN ref.job_function f ON f.function_name = v.fn;

INSERT INTO ref.identifier_type (code, label_key, sort_order, validation_regex, applies_to_person, applies_to_organisation, country_id)
SELECT v.code, ref.label_for('enum.identifier_type', v.label), v.ord, v.regex, v.person, v.org, c.id
  FROM (VALUES ('aadhaar',  'Aadhaar',  1, '^[2-9][0-9]{11}$',                                    true,  false, 'IN'),
               ('pan',      'PAN',      2, '^[A-Z]{5}[0-9]{4}[A-Z]$',                             true,  true,  'IN'),
               ('passport', 'Passport', 3, NULL,                                                  true,  false, NULL),
               ('gstin',    'GSTIN',    4, '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',    false, true,  'IN'),
               ('cin',      'CIN',      5, '^[LU][0-9]{5}[A-Z]{2}[0-9]{4}[A-Z]{3}[0-9]{6}$',      false, true,  'IN'),
               ('ein',      'EIN',      6, '^[0-9]{2}-[0-9]{7}$',                                 false, true,  'US'))
       v(code, label, ord, regex, person, org, iso2)
  LEFT JOIN ref.country c ON c.iso_alpha2 = v.iso2;

-- =====================================================================================================
-- M6: unique and check constraints, indexes (ref)
-- =====================================================================================================

ALTER TABLE ref.currency
  ADD CONSTRAINT ck_currency_minor_unit CHECK (minor_unit BETWEEN 0 AND 4);

ALTER TABLE ref.country
  ADD CONSTRAINT uq_country_iso_alpha3 UNIQUE (iso_alpha3),
  ADD CONSTRAINT ck_country_iso_alpha2_format CHECK (iso_alpha2 ~ '^[A-Z]{2}$'),
  ADD CONSTRAINT ck_country_iso_alpha3_format CHECK (iso_alpha3 ~ '^[A-Z]{3}$'),
  ADD CONSTRAINT ck_country_phone_prefix_format CHECK (phone_prefix ~ '^\+[1-9][0-9]{0,3}$');

ALTER TABLE ref.state
  ADD CONSTRAINT uq_state_country_id_state_name UNIQUE (country_id, state_name),
  ADD CONSTRAINT uq_state_iso_subdivision UNIQUE (iso_subdivision),
  ADD CONSTRAINT ck_state_iso_subdivision_format CHECK (iso_subdivision ~ '^[A-Z]{2}-[A-Z0-9]{1,3}$');

ALTER TABLE ref.city
  ADD CONSTRAINT uq_city_country_id_state_id_city_name UNIQUE NULLS NOT DISTINCT (country_id, state_id, city_name),
  ADD CONSTRAINT uq_city_geonames_id UNIQUE (geonames_id),
  ADD CONSTRAINT ck_city_coordinates_pair CHECK ((latitude IS NULL) = (longitude IS NULL));
CREATE INDEX idx_city_state_id ON ref.city (state_id);
CREATE INDEX idx_city_city_name_trgm ON ref.city USING gin (city_name gin_trgm_ops);

ALTER TABLE ref.skill_category
  ADD CONSTRAINT uq_skill_category_category_name UNIQUE (category_name),
  ADD CONSTRAINT ck_skill_category_not_own_parent CHECK (parent_skill_category_id <> id);

CREATE UNIQUE INDEX uq_skill_skill_name_lower ON ref.skill (lower(skill_name));
CREATE INDEX idx_skill_skill_category_id ON ref.skill (skill_category_id);
CREATE INDEX idx_skill_skill_name_trgm ON ref.skill USING gin (skill_name gin_trgm_ops);

ALTER TABLE ref.qualification ADD CONSTRAINT uq_qualification_qualification_name UNIQUE (qualification_name);
ALTER TABLE ref.field_of_study ADD CONSTRAINT uq_field_of_study_field_name UNIQUE (field_name);
ALTER TABLE ref.institution ADD CONSTRAINT uq_institution_institution_name_country_id UNIQUE (institution_name, country_id);
CREATE INDEX idx_institution_institution_name_trgm ON ref.institution USING gin (institution_name gin_trgm_ops);

ALTER TABLE ref.industry
  ADD CONSTRAINT uq_industry_industry_name UNIQUE (industry_name),
  ADD CONSTRAINT ck_industry_not_own_parent CHECK (parent_industry_id <> id);
ALTER TABLE ref.job_function ADD CONSTRAINT uq_job_function_function_name UNIQUE (function_name);
ALTER TABLE ref.job_role ADD CONSTRAINT uq_job_role_job_function_id_role_name UNIQUE (job_function_id, role_name);

ALTER TABLE ref.pay_period          ADD CONSTRAINT ck_pay_period_annual_multiplier CHECK (annual_multiplier > 0);
ALTER TABLE ref.notice_period       ADD CONSTRAINT ck_notice_period_notice_days CHECK (notice_days >= 0);
ALTER TABLE ref.proficiency_level   ADD CONSTRAINT ck_proficiency_level_level_rank CHECK (level_rank > 0);
ALTER TABLE ref.qualification_level ADD CONSTRAINT ck_qualification_level_level_rank CHECK (level_rank > 0);
ALTER TABLE ref.application_status  ADD CONSTRAINT ck_application_status_pipeline_rank CHECK (pipeline_rank > 0);
ALTER TABLE ref.identifier_type     ADD CONSTRAINT ck_identifier_type_applies_to CHECK (applies_to_person OR applies_to_organisation);
