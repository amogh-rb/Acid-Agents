-- Jobs and Applications (schema job). Owner B. Entities and relationships: docs/phase1/entities.md, relationships.md.
--   M4: columns, PKs and FKs (ON DELETE as in relationships.md), plus the deferred profile -> job FKs.
--   M6: unique / check constraints, transition trigger, append-only guard test, indexes (M6 section below).
-- job.application is hash-partitioned on candidate_profile_id (32 partitions, decision D5): the one-application-per-
-- candidate-per-job key includes the partition key, and every FK into application is composite
-- (application_id, candidate_profile_id) so no FK has to be rebuilt when volumes grow.

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE job.job_requirement (
  id                           bigint GENERATED ALWAYS AS IDENTITY,
  organisation_id              bigint       NOT NULL,
  client_organisation_id       bigint,
  posted_by_app_user_id        bigint       NOT NULL,
  job_title                    varchar(200) NOT NULL,
  description                  text         NOT NULL,
  description_language_id      bigint,
  job_category_code            d_code       NOT NULL,
  employment_type_code         d_code       NOT NULL,
  work_type_code               d_code       NOT NULL,
  job_role_id                  bigint       NOT NULL,
  industry_id                  bigint,
  job_requirement_status_code  d_code       NOT NULL DEFAULT 'draft',
  publish_state_code           d_code       NOT NULL DEFAULT 'unpublished',
  salary_disclosure_code       d_code       NOT NULL DEFAULT 'not_disclosed',
  salary_min                   d_money,
  salary_max                   d_money,
  currency_code                d_currency_code,
  pay_period_code              d_code,
  experience_min_months        integer,
  experience_max_months        integer,
  notice_period_code           d_code,
  is_open_to_consultant        boolean      NOT NULL DEFAULT false,
  consultant_fee_pct           d_pct,
  published_at                 timestamptz,
  application_deadline         date,
  legacy_source_system         varchar(30),
  legacy_source_id             varchar(64),
  created_at                   timestamptz  NOT NULL DEFAULT now(),
  created_by                   bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                   timestamptz  NOT NULL DEFAULT now(),
  updated_by                   bigint       NOT NULL DEFAULT public.current_actor_id(),
  deleted_at                   timestamptz,
  CONSTRAINT pk_job_requirement PRIMARY KEY (id),
  CONSTRAINT fk_job_requirement_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_client_organisation_id FOREIGN KEY (client_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_posted_by_app_user_id FOREIGN KEY (posted_by_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_description_language_id FOREIGN KEY (description_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_job_category_code FOREIGN KEY (job_category_code) REFERENCES ref.job_category (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_employment_type_code FOREIGN KEY (employment_type_code) REFERENCES ref.employment_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_work_type_code FOREIGN KEY (work_type_code) REFERENCES ref.work_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_job_role_id FOREIGN KEY (job_role_id) REFERENCES ref.job_role (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_industry_id FOREIGN KEY (industry_id) REFERENCES ref.industry (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_job_requirement_status_code FOREIGN KEY (job_requirement_status_code) REFERENCES ref.job_requirement_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_publish_state_code FOREIGN KEY (publish_state_code) REFERENCES ref.publish_state (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_salary_disclosure_code FOREIGN KEY (salary_disclosure_code) REFERENCES ref.disclosure (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_currency_code FOREIGN KEY (currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_pay_period_code FOREIGN KEY (pay_period_code) REFERENCES ref.pay_period (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_notice_period_code FOREIGN KEY (notice_period_code) REFERENCES ref.notice_period (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.job_requirement IS '[soft-delete] Job posting (non-gig categories): owner and client, category, role, salary with disclosure, experience range, lifecycle, publish state, consultant openness';
COMMENT ON COLUMN job.job_requirement.organisation_id IS '[Internal] Owning employer or agency (RLS key in M18)';
COMMENT ON COLUMN job.job_requirement.client_organisation_id IS '[Internal] Client the agency hires for; null: direct employer hiring for itself';
COMMENT ON COLUMN job.job_requirement.posted_by_app_user_id IS '[Internal] Recruiter accountable for the posting';
COMMENT ON COLUMN job.job_requirement.job_title IS '[Public] Title as posted, max 200';
COMMENT ON COLUMN job.job_requirement.description IS '[Public] Full job description; unbounded: job descriptions are free-form and length varies widely (docket allows it)';
COMMENT ON COLUMN job.job_requirement.description_language_id IS '[Public] Language of description as entered or detected; null: not detected (RG7)';
COMMENT ON COLUMN job.job_requirement.job_category_code IS '[Public] general_staffing, permanent, apprentice, campus ... (gig uses the gig subsystem)';
COMMENT ON COLUMN job.job_requirement.employment_type_code IS '[Public] Permanent, contract ...';
COMMENT ON COLUMN job.job_requirement.work_type_code IS '[Public] Onsite, remote, hybrid';
COMMENT ON COLUMN job.job_requirement.job_role_id IS '[Public] Standard role for search and analytics';
COMMENT ON COLUMN job.job_requirement.industry_id IS '[Public] Industry of the job; null: inherits the organisation industry';
COMMENT ON COLUMN job.job_requirement.job_requirement_status_code IS '[Internal] Lifecycle; default draft';
COMMENT ON COLUMN job.job_requirement.publish_state_code IS '[Internal] Visibility; default unpublished';
COMMENT ON COLUMN job.job_requirement.salary_disclosure_code IS '[Public] disclosed / not_disclosed / not_applicable (unpaid apprenticeship); default not_disclosed';
COMMENT ON COLUMN job.job_requirement.salary_min IS '[Public] Minimum salary; null: not disclosed or not applicable (CHECK in M6), or open-ended upper-only range';
COMMENT ON COLUMN job.job_requirement.salary_max IS '[Public] Maximum salary; null: not disclosed, not applicable or no upper bound stated';
COMMENT ON COLUMN job.job_requirement.currency_code IS '[Public] Currency of the salary range; null: salary not disclosed';
COMMENT ON COLUMN job.job_requirement.pay_period_code IS '[Public] Period the salary is quoted in; null: salary not disclosed';
COMMENT ON COLUMN job.job_requirement.experience_min_months IS '[Public] Minimum experience in months (0 = freshers welcome); null: no minimum stated';
COMMENT ON COLUMN job.job_requirement.experience_max_months IS '[Public] Maximum experience in months; null: no upper bound';
COMMENT ON COLUMN job.job_requirement.notice_period_code IS '[Public] Longest acceptable notice period; null: no notice-period requirement';
COMMENT ON COLUMN job.job_requirement.is_open_to_consultant IS '[Internal] Consultants may source for this job (B46 rule); default false';
COMMENT ON COLUMN job.job_requirement.consultant_fee_pct IS '[Internal] Consultant fee as % of first-year CTC; null: not open to consultants (CHECK in M6)';
COMMENT ON COLUMN job.job_requirement.published_at IS '[Internal] First publish instant (UTC); null: never published';
COMMENT ON COLUMN job.job_requirement.application_deadline IS '[Public] Last date to apply; null: open until closed';
COMMENT ON COLUMN job.job_requirement.legacy_source_system IS '[Internal] Legacy system the posting was migrated from; null: created natively';
COMMENT ON COLUMN job.job_requirement.legacy_source_id IS '[Internal] Record id in the legacy system; nofk: external identifier; null: created natively';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE job.job_position (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  job_requirement_id        bigint      NOT NULL,
  position_number           smallint    NOT NULL,
  filled_by_application_id  bigint,
  filled_by_candidate_profile_id bigint,
  filled_on                 date,
  created_at                timestamptz NOT NULL DEFAULT now(),
  created_by                bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  updated_by                bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_position PRIMARY KEY (id),
  CONSTRAINT fk_job_position_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_job_position_filled_by_candidate_profile_id FOREIGN KEY (filled_by_candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.job_position IS '[hard-delete] One opening within a requirement and its fill state (positions count = rows; owned by the requirement)';
COMMENT ON COLUMN job.job_position.job_requirement_id IS '[Internal] Owning requirement';
COMMENT ON COLUMN job.job_position.position_number IS '[Internal] 1..n within the requirement';
COMMENT ON COLUMN job.job_position.filled_by_application_id IS '[Internal] Application that filled the opening; null: still open (FK added below)';
COMMENT ON COLUMN job.job_position.filled_by_candidate_profile_id IS '[Internal] Candidate hired into the opening (partition key of the filling application); null: still open';
COMMENT ON COLUMN job.job_position.filled_on IS '[Internal] Date filled; null: still open';

CREATE TABLE job.job_requirement_location (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  job_requirement_id  bigint      NOT NULL,
  city_id             bigint      NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_requirement_location PRIMARY KEY (id),
  CONSTRAINT fk_job_requirement_location_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_job_requirement_location_city_id FOREIGN KEY (city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.job_requirement_location IS '[hard-delete] City a requirement is open in (junction, owned by the requirement)';
COMMENT ON COLUMN job.job_requirement_location.job_requirement_id IS '[Internal] Owning requirement';
COMMENT ON COLUMN job.job_requirement_location.city_id IS '[Public] Job location';

CREATE TABLE job.job_requirement_skill (
  id                          bigint GENERATED ALWAYS AS IDENTITY,
  job_requirement_id          bigint      NOT NULL,
  skill_id                    bigint      NOT NULL,
  is_mandatory                boolean     NOT NULL DEFAULT true,
  min_proficiency_level_code  d_code,
  min_experience_months       integer,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  created_by                  bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  updated_by                  bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_requirement_skill PRIMARY KEY (id),
  CONSTRAINT fk_job_requirement_skill_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_job_requirement_skill_skill_id FOREIGN KEY (skill_id) REFERENCES ref.skill (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_skill_min_proficiency_level_code FOREIGN KEY (min_proficiency_level_code) REFERENCES ref.proficiency_level (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.job_requirement_skill IS '[hard-delete] Skill required by a requirement (junction, owned by the requirement)';
COMMENT ON COLUMN job.job_requirement_skill.job_requirement_id IS '[Internal] Owning requirement';
COMMENT ON COLUMN job.job_requirement_skill.skill_id IS '[Public] Skill required';
COMMENT ON COLUMN job.job_requirement_skill.is_mandatory IS '[Public] Must-have (true) or nice-to-have; default true';
COMMENT ON COLUMN job.job_requirement_skill.min_proficiency_level_code IS '[Public] Minimum proficiency; null: any proficiency accepted';
COMMENT ON COLUMN job.job_requirement_skill.min_experience_months IS '[Public] Minimum months using the skill; null: no minimum';

CREATE TABLE job.job_requirement_qualification (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  job_requirement_id  bigint      NOT NULL,
  qualification_id    bigint      NOT NULL,
  field_of_study_id   bigint,
  is_mandatory        boolean     NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_requirement_qualification PRIMARY KEY (id),
  CONSTRAINT fk_job_requirement_qualification_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_job_requirement_qualification_qualification_id FOREIGN KEY (qualification_id) REFERENCES ref.qualification (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_job_requirement_qualification_field_of_study_id FOREIGN KEY (field_of_study_id) REFERENCES ref.field_of_study (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.job_requirement_qualification IS '[hard-delete] Qualification accepted for a requirement (junction, owned by the requirement)';
COMMENT ON COLUMN job.job_requirement_qualification.job_requirement_id IS '[Internal] Owning requirement';
COMMENT ON COLUMN job.job_requirement_qualification.qualification_id IS '[Public] Qualification accepted';
COMMENT ON COLUMN job.job_requirement_qualification.field_of_study_id IS '[Public] Required specialisation; null: any field accepted';
COMMENT ON COLUMN job.job_requirement_qualification.is_mandatory IS '[Public] Required (true) or preferred; default true';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE job.questionnaire (
  id                   bigint GENERATED ALWAYS AS IDENTITY,
  organisation_id      bigint       NOT NULL,
  questionnaire_title  varchar(200) NOT NULL,
  language_id          bigint,
  is_active            boolean      NOT NULL DEFAULT true,
  created_at           timestamptz  NOT NULL DEFAULT now(),
  created_by           bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at           timestamptz  NOT NULL DEFAULT now(),
  updated_by           bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_questionnaire PRIMARY KEY (id),
  CONSTRAINT fk_questionnaire_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_questionnaire_language_id FOREIGN KEY (language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.questionnaire IS '[hard-delete] Reusable screening questionnaire owned by an organisation';
COMMENT ON COLUMN job.questionnaire.organisation_id IS '[Internal] Owning organisation';
COMMENT ON COLUMN job.questionnaire.questionnaire_title IS '[Internal] Title, max 200';
COMMENT ON COLUMN job.questionnaire.language_id IS '[Internal] Language the questions are written in (RG7); null: not stated';
COMMENT ON COLUMN job.questionnaire.is_active IS '[Internal] Can be attached to new jobs; default true';

CREATE TABLE job.questionnaire_question (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  questionnaire_id    bigint        NOT NULL,
  question_order      smallint      NOT NULL,
  question_text       varchar(1000) NOT NULL,
  question_type_code  d_code        NOT NULL,
  is_mandatory        boolean       NOT NULL DEFAULT true,
  is_knockout         boolean       NOT NULL DEFAULT false,
  created_at          timestamptz   NOT NULL DEFAULT now(),
  created_by          bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at          timestamptz   NOT NULL DEFAULT now(),
  updated_by          bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_questionnaire_question PRIMARY KEY (id),
  CONSTRAINT fk_questionnaire_question_questionnaire_id FOREIGN KEY (questionnaire_id) REFERENCES job.questionnaire (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_questionnaire_question_question_type_code FOREIGN KEY (question_type_code) REFERENCES ref.question_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.questionnaire_question IS '[hard-delete] Ordered question in a questionnaire (owned by the questionnaire)';
COMMENT ON COLUMN job.questionnaire_question.questionnaire_id IS '[Internal] Owning questionnaire';
COMMENT ON COLUMN job.questionnaire_question.question_order IS '[Internal] Display order within the questionnaire';
COMMENT ON COLUMN job.questionnaire_question.question_text IS '[Internal] Question as written, max 1000 (language on the questionnaire)';
COMMENT ON COLUMN job.questionnaire_question.question_type_code IS '[Internal] Answer format';
COMMENT ON COLUMN job.questionnaire_question.is_mandatory IS '[Internal] Answer required to apply; default true';
COMMENT ON COLUMN job.questionnaire_question.is_knockout IS '[Internal] A knockout answer auto-rejects the application; default false';

CREATE TABLE job.question_option (
  id                         bigint GENERATED ALWAYS AS IDENTITY,
  questionnaire_question_id  bigint       NOT NULL,
  option_order               smallint     NOT NULL,
  option_text                varchar(300) NOT NULL,
  is_knockout_answer         boolean      NOT NULL DEFAULT false,
  created_at                 timestamptz  NOT NULL DEFAULT now(),
  created_by                 bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                 timestamptz  NOT NULL DEFAULT now(),
  updated_by                 bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_question_option PRIMARY KEY (id),
  CONSTRAINT fk_question_option_questionnaire_question_id FOREIGN KEY (questionnaire_question_id) REFERENCES job.questionnaire_question (id) ON UPDATE NO ACTION ON DELETE CASCADE
);
COMMENT ON TABLE  job.question_option IS '[hard-delete] Allowed answer of a choice question (owned by the question)';
COMMENT ON COLUMN job.question_option.questionnaire_question_id IS '[Internal] Owning question';
COMMENT ON COLUMN job.question_option.option_order IS '[Internal] Display order';
COMMENT ON COLUMN job.question_option.option_text IS '[Internal] Answer text, max 300';
COMMENT ON COLUMN job.question_option.is_knockout_answer IS '[Internal] Choosing it rejects the application when the question is a knockout; default false';

CREATE TABLE job.job_requirement_questionnaire (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  job_requirement_id  bigint      NOT NULL,
  questionnaire_id    bigint      NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_requirement_questionnaire PRIMARY KEY (id),
  CONSTRAINT fk_job_requirement_questionnaire_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_job_requirement_questionnaire_questionnaire_id FOREIGN KEY (questionnaire_id) REFERENCES job.questionnaire (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.job_requirement_questionnaire IS '[hard-delete] Questionnaire attached to a requirement (junction, owned by the requirement)';
COMMENT ON COLUMN job.job_requirement_questionnaire.job_requirement_id IS '[Internal] Owning requirement';
COMMENT ON COLUMN job.job_requirement_questionnaire.questionnaire_id IS '[Internal] Attached questionnaire (cannot be deleted while attached)';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE job.application (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  job_requirement_id       bigint        NOT NULL,
  candidate_profile_id     bigint        NOT NULL,
  application_status_code  d_code        NOT NULL DEFAULT 'applied',
  application_source_code  d_code        NOT NULL DEFAULT 'direct',
  rejection_reason_code    d_code,
  resume_version_id        bigint,
  referral_id              bigint,
  cover_note               varchar(2000),
  applied_at               timestamptz   NOT NULL DEFAULT now(),
  status_changed_at        timestamptz   NOT NULL DEFAULT now(),
  created_at               timestamptz   NOT NULL DEFAULT now(),
  created_by               bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz   NOT NULL DEFAULT now(),
  updated_by               bigint        NOT NULL DEFAULT public.current_actor_id(),
  deleted_at               timestamptz,
  CONSTRAINT pk_application PRIMARY KEY (id, candidate_profile_id),
  CONSTRAINT fk_application_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_application_status_code FOREIGN KEY (application_status_code) REFERENCES ref.application_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_application_source_code FOREIGN KEY (application_source_code) REFERENCES ref.application_source (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_rejection_reason_code FOREIGN KEY (rejection_reason_code) REFERENCES ref.rejection_reason (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_resume_version_id FOREIGN KEY (resume_version_id) REFERENCES profile.resume_version (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_referral_id FOREIGN KEY (referral_id) REFERENCES profile.referral (id) ON UPDATE NO ACTION ON DELETE RESTRICT
) PARTITION BY HASH (candidate_profile_id);
COMMENT ON TABLE  job.application IS '[soft-delete] Candidate application to a requirement: current status, source, resume, applied_at; one per candidate per job. Retention: anonymised with the profile';
COMMENT ON COLUMN job.application.job_requirement_id IS '[Internal] Job applied to';
COMMENT ON COLUMN job.application.candidate_profile_id IS '[Internal] Applicant';
COMMENT ON COLUMN job.application.application_status_code IS '[Internal] Current pipeline status; history in application_status_history; default applied';
COMMENT ON COLUMN job.application.application_source_code IS '[Internal] How the application arrived; default direct';
COMMENT ON COLUMN job.application.rejection_reason_code IS '[Internal] Why rejected; null: not rejected (CHECK in M6)';
COMMENT ON COLUMN job.application.resume_version_id IS '[Personal] Resume attached; null: applied with the profile only';
COMMENT ON COLUMN job.application.referral_id IS '[Internal] Referral that led to the application; null: not a referral';
COMMENT ON COLUMN job.application.cover_note IS '[Personal] Note to the employer, max 2000; null: none written';
COMMENT ON COLUMN job.application.applied_at IS '[Internal] Application instant (UTC)';

-- 32 hash partitions: candidates apply roughly uniformly, so partitions stay even (applications per job are Zipf-skewed,
-- which is why job_requirement_id is not the key). Laptop scale ~156K rows each; full scale ~3.1M each (D5).
DO $$
BEGIN
  FOR i IN 0..31 LOOP
    EXECUTE format('CREATE TABLE job.%I PARTITION OF job.application FOR VALUES WITH (MODULUS 32, REMAINDER %s)',
                   'application_h' || lpad(i::text, 2, '0'), i);
  END LOOP;
END $$;
COMMENT ON COLUMN job.application.status_changed_at IS '[Internal] Last status change instant (UTC)';

CREATE TABLE job.application_answer (
  id                         bigint GENERATED ALWAYS AS IDENTITY,
  application_id             bigint        NOT NULL,
  candidate_profile_id       bigint        NOT NULL,
  questionnaire_question_id  bigint        NOT NULL,
  question_option_id         bigint,
  answer_text                varchar(2000),
  answer_number              numeric(14,2),
  created_at                 timestamptz   NOT NULL DEFAULT now(),
  created_by                 bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at                 timestamptz   NOT NULL DEFAULT now(),
  updated_by                 bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_application_answer PRIMARY KEY (id),
  CONSTRAINT fk_application_answer_application FOREIGN KEY (application_id, candidate_profile_id)
    REFERENCES job.application (id, candidate_profile_id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_application_answer_questionnaire_question_id FOREIGN KEY (questionnaire_question_id) REFERENCES job.questionnaire_question (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_answer_question_option_id FOREIGN KEY (question_option_id) REFERENCES job.question_option (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.application_answer IS '[hard-delete] Candidate answer to a screening question (owned by the application)';
COMMENT ON COLUMN job.application_answer.application_id IS '[Internal] Owning application';
COMMENT ON COLUMN job.application_answer.candidate_profile_id IS '[Internal] Applicant; partition key of job.application, part of the composite FK (D5)';
COMMENT ON COLUMN job.application_answer.questionnaire_question_id IS '[Internal] Question answered';
COMMENT ON COLUMN job.application_answer.question_option_id IS '[Personal] Chosen option; null: free-text or numeric answer';
COMMENT ON COLUMN job.application_answer.answer_text IS '[Personal] Free-text answer, max 2000; null: choice or numeric answer';
COMMENT ON COLUMN job.application_answer.answer_number IS '[Personal] Numeric answer (years, count); null: choice or text answer';

CREATE TABLE job.application_status_history (
  id                           bigint GENERATED ALWAYS AS IDENTITY,
  application_id               bigint       NOT NULL,
  candidate_profile_id         bigint       NOT NULL,
  from_application_status_code d_code,
  to_application_status_code   d_code       NOT NULL,
  changed_at                   timestamptz  NOT NULL DEFAULT now(),
  change_reason                varchar(500),
  created_at                   timestamptz  NOT NULL DEFAULT now(),
  created_by                   bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_application_status_history PRIMARY KEY (id),
  CONSTRAINT fk_application_status_history_application FOREIGN KEY (application_id, candidate_profile_id)
    REFERENCES job.application (id, candidate_profile_id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_status_history_from_application_status_code FOREIGN KEY (from_application_status_code) REFERENCES ref.application_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_status_history_to_application_status_code FOREIGN KEY (to_application_status_code) REFERENCES ref.application_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.application_status_history IS '[append-only] Every application status transition with actor (created_by), time and reason';
COMMENT ON COLUMN job.application_status_history.application_id IS '[Internal] Application';
COMMENT ON COLUMN job.application_status_history.candidate_profile_id IS '[Internal] Applicant; partition key of job.application, part of the composite FK (D5)';
COMMENT ON COLUMN job.application_status_history.from_application_status_code IS '[Internal] Previous status; null: first entry (applied) has no previous status';
COMMENT ON COLUMN job.application_status_history.to_application_status_code IS '[Internal] New status';
COMMENT ON COLUMN job.application_status_history.changed_at IS '[Internal] Transition instant (UTC)';
COMMENT ON COLUMN job.application_status_history.change_reason IS '[Internal] Note recorded with the change, max 500; null: no note';

CREATE TABLE job.application_status_transition (
  id                            bigint GENERATED ALWAYS AS IDENTITY,
  from_application_status_code  d_code      NOT NULL,
  to_application_status_code    d_code      NOT NULL,
  is_active                     boolean     NOT NULL DEFAULT true,
  created_at                    timestamptz NOT NULL DEFAULT now(),
  created_by                    bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                    timestamptz NOT NULL DEFAULT now(),
  updated_by                    bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_application_status_transition PRIMARY KEY (id),
  CONSTRAINT fk_application_status_transition_from_application_status_code FOREIGN KEY (from_application_status_code) REFERENCES ref.application_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_application_status_transition_to_application_status_code FOREIGN KEY (to_application_status_code) REFERENCES ref.application_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.application_status_transition IS '[hard-delete] Legal (from, to) status moves read by trg_application_status_transition';
COMMENT ON COLUMN job.application_status_transition.from_application_status_code IS '[Internal] Status moved from';
COMMENT ON COLUMN job.application_status_transition.to_application_status_code IS '[Internal] Status moved to';
COMMENT ON COLUMN job.application_status_transition.is_active IS '[Internal] Move currently allowed; default true';

INSERT INTO job.application_status_transition (from_application_status_code, to_application_status_code)
VALUES ('applied', 'shortlisted'), ('applied', 'rejected'), ('applied', 'withdrawn'),
       ('shortlisted', 'interviewed'), ('shortlisted', 'rejected'), ('shortlisted', 'withdrawn'),
       ('interviewed', 'offered'), ('interviewed', 'rejected'), ('interviewed', 'withdrawn'),
       ('offered', 'joined'), ('offered', 'rejected'), ('offered', 'withdrawn');

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE job.shortlist (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  organisation_id     bigint       NOT NULL,
  owner_app_user_id   bigint       NOT NULL,
  job_requirement_id  bigint,
  shortlist_name      varchar(150) NOT NULL,
  created_at          timestamptz  NOT NULL DEFAULT now(),
  created_by          bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at          timestamptz  NOT NULL DEFAULT now(),
  updated_by          bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_shortlist PRIMARY KEY (id),
  CONSTRAINT fk_shortlist_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_shortlist_owner_app_user_id FOREIGN KEY (owner_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_shortlist_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.shortlist IS '[hard-delete] Named shortlist owned by an organisation (Sourcing references it)';
COMMENT ON COLUMN job.shortlist.organisation_id IS '[Internal] Owning organisation';
COMMENT ON COLUMN job.shortlist.owner_app_user_id IS '[Internal] Recruiter who maintains it';
COMMENT ON COLUMN job.shortlist.job_requirement_id IS '[Internal] Job the shortlist is for; null: talent-pool shortlist';
COMMENT ON COLUMN job.shortlist.shortlist_name IS '[Internal] Name, max 150';

CREATE TABLE job.shortlist_entry (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  shortlist_id          bigint       NOT NULL,
  candidate_profile_id  bigint       NOT NULL,
  entry_note            varchar(500),
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  deleted_at            timestamptz,
  CONSTRAINT pk_shortlist_entry PRIMARY KEY (id),
  CONSTRAINT fk_shortlist_entry_shortlist_id FOREIGN KEY (shortlist_id) REFERENCES job.shortlist (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_shortlist_entry_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.shortlist_entry IS '[soft-delete] Candidate on a shortlist; removal sets deleted_at so shortlist history (who added, when removed) is kept';
COMMENT ON COLUMN job.shortlist_entry.shortlist_id IS '[Internal] Owning shortlist';
COMMENT ON COLUMN job.shortlist_entry.candidate_profile_id IS '[Internal] Candidate shortlisted';
COMMENT ON COLUMN job.shortlist_entry.entry_note IS '[Internal] Recruiter note, max 500; null: no note';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE job.interview (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  application_id           bigint        NOT NULL,
  candidate_profile_id     bigint        NOT NULL,
  round_number             smallint      NOT NULL,
  interview_mode_code      d_code        NOT NULL,
  interview_status_code    d_code        NOT NULL DEFAULT 'scheduled',
  interview_outcome_code   d_code,
  interviewer_app_user_id  bigint,
  scheduled_start          timestamptz   NOT NULL,
  scheduled_end            timestamptz   NOT NULL,
  timezone_id              bigint,
  venue                    varchar(300),
  meeting_url              varchar(500),
  feedback                 varchar(4000),
  created_at               timestamptz   NOT NULL DEFAULT now(),
  created_by               bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz   NOT NULL DEFAULT now(),
  updated_by               bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_interview PRIMARY KEY (id),
  CONSTRAINT fk_interview_application FOREIGN KEY (application_id, candidate_profile_id)
    REFERENCES job.application (id, candidate_profile_id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_interview_interview_mode_code FOREIGN KEY (interview_mode_code) REFERENCES ref.interview_mode (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_interview_interview_status_code FOREIGN KEY (interview_status_code) REFERENCES ref.interview_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_interview_interview_outcome_code FOREIGN KEY (interview_outcome_code) REFERENCES ref.interview_outcome (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_interview_interviewer_app_user_id FOREIGN KEY (interviewer_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_interview_timezone_id FOREIGN KEY (timezone_id) REFERENCES ref.timezone (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.interview IS '[hard-delete] Interview round of an application';
COMMENT ON COLUMN job.interview.application_id IS '[Internal] Application interviewed';
COMMENT ON COLUMN job.interview.candidate_profile_id IS '[Internal] Applicant; partition key of job.application, part of the composite FK (D5)';
COMMENT ON COLUMN job.interview.round_number IS '[Internal] 1..n per application';
COMMENT ON COLUMN job.interview.interview_mode_code IS '[Internal] In person, video, phone';
COMMENT ON COLUMN job.interview.interview_status_code IS '[Internal] Scheduling state; default scheduled';
COMMENT ON COLUMN job.interview.interview_outcome_code IS '[Internal] Result; null: not yet held (CHECK in M6: set only when completed)';
COMMENT ON COLUMN job.interview.interviewer_app_user_id IS '[Internal] Lead interviewer; null: panel not assigned yet';
COMMENT ON COLUMN job.interview.scheduled_start IS '[Internal] Start (UTC)';
COMMENT ON COLUMN job.interview.scheduled_end IS '[Internal] End (UTC)';
COMMENT ON COLUMN job.interview.timezone_id IS '[Internal] Zone the schedule is shown in to the candidate (RG3 source time zone); null: shown in the viewer zone';
COMMENT ON COLUMN job.interview.venue IS '[Internal] Address for in-person rounds, max 300; null: not in person';
COMMENT ON COLUMN job.interview.meeting_url IS '[Internal] Video link, max 500; null: not a video round';
COMMENT ON COLUMN job.interview.feedback IS '[Personal] Interviewer feedback about the candidate, max 4000; null: not written yet';

CREATE TABLE job.offer (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  application_id         bigint          NOT NULL,
  candidate_profile_id   bigint          NOT NULL,
  offer_status_code      d_code          NOT NULL DEFAULT 'extended',
  ctc_amount             d_money         NOT NULL,
  ctc_currency_code      d_currency_code NOT NULL,
  ctc_pay_period_code    d_code          NOT NULL,
  offered_on             date            NOT NULL,
  proposed_joining_date  date,
  valid_until            date,
  responded_at           timestamptz,
  created_at             timestamptz     NOT NULL DEFAULT now(),
  created_by             bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz     NOT NULL DEFAULT now(),
  updated_by             bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_offer PRIMARY KEY (id),
  CONSTRAINT fk_offer_application FOREIGN KEY (application_id, candidate_profile_id)
    REFERENCES job.application (id, candidate_profile_id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_offer_offer_status_code FOREIGN KEY (offer_status_code) REFERENCES ref.offer_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_offer_ctc_currency_code FOREIGN KEY (ctc_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_offer_ctc_pay_period_code FOREIGN KEY (ctc_pay_period_code) REFERENCES ref.pay_period (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.offer IS '[hard-delete] Offer made on an application; a revised offer is a new row';
COMMENT ON COLUMN job.offer.application_id IS '[Internal] Application';
COMMENT ON COLUMN job.offer.candidate_profile_id IS '[Internal] Applicant; partition key of job.application, part of the composite FK (D5)';
COMMENT ON COLUMN job.offer.offer_status_code IS '[Internal] State; default extended';
COMMENT ON COLUMN job.offer.ctc_amount IS '[Personal] Cost to company offered';
COMMENT ON COLUMN job.offer.ctc_currency_code IS '[Personal] Currency of ctc_amount';
COMMENT ON COLUMN job.offer.ctc_pay_period_code IS '[Personal] Period ctc_amount is quoted in';
COMMENT ON COLUMN job.offer.offered_on IS '[Internal] Date the offer was made';
COMMENT ON COLUMN job.offer.proposed_joining_date IS '[Internal] Joining date proposed; null: to be agreed';
COMMENT ON COLUMN job.offer.valid_until IS '[Internal] Last date to accept; null: no expiry';
COMMENT ON COLUMN job.offer.responded_at IS '[Internal] When the candidate accepted or declined; null: no response yet';

CREATE TABLE job.joining (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  application_id         bigint      NOT NULL,
  candidate_profile_id   bigint      NOT NULL,
  offer_id               bigint      NOT NULL,
  joining_status_code    d_code      NOT NULL DEFAULT 'expected',
  expected_joining_date  date        NOT NULL,
  actual_joining_date    date,
  created_at             timestamptz NOT NULL DEFAULT now(),
  created_by             bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_joining PRIMARY KEY (id),
  CONSTRAINT fk_joining_application FOREIGN KEY (application_id, candidate_profile_id)
    REFERENCES job.application (id, candidate_profile_id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_joining_offer_id FOREIGN KEY (offer_id) REFERENCES job.offer (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_joining_joining_status_code FOREIGN KEY (joining_status_code) REFERENCES ref.joining_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.joining IS '[hard-delete] Joining against an accepted offer; one per application';
COMMENT ON COLUMN job.joining.application_id IS '[Internal] Application (unique in M6)';
COMMENT ON COLUMN job.joining.candidate_profile_id IS '[Internal] Applicant; partition key of job.application, part of the composite FK (D5)';
COMMENT ON COLUMN job.joining.offer_id IS '[Internal] Accepted offer (unique in M6)';
COMMENT ON COLUMN job.joining.joining_status_code IS '[Internal] expected, joined, no_show, deferred; default expected';
COMMENT ON COLUMN job.joining.expected_joining_date IS '[Internal] Agreed joining date';
COMMENT ON COLUMN job.joining.actual_joining_date IS '[Internal] Date actually joined; null: not joined yet';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE job.saved_search (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint       NOT NULL,
  search_name           varchar(100) NOT NULL,
  search_criteria       jsonb        NOT NULL,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_saved_search PRIMARY KEY (id),
  CONSTRAINT fk_saved_search_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE
);
COMMENT ON TABLE  job.saved_search IS '[hard-delete] Candidate saved job search (owned by the candidate); job alerts on it live in Notifications';
COMMENT ON COLUMN job.saved_search.candidate_profile_id IS '[Internal] Owning candidate';
COMMENT ON COLUMN job.saved_search.search_name IS '[Personal] Name, max 100';
COMMENT ON COLUMN job.saved_search.search_criteria IS '[Personal] Keywords and filters as JSON (role, city, salary, work type)';

CREATE TABLE job.job_search_event (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint,
  session_token         varchar(64),
  search_query          varchar(500),
  search_filters        jsonb,
  result_count          integer      NOT NULL,
  searched_at           timestamptz  NOT NULL DEFAULT now(),
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_job_search_event PRIMARY KEY (id),
  CONSTRAINT fk_job_search_event_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  job.job_search_event IS '[append-only] Each job search run by a candidate or guest (job search history)';
COMMENT ON COLUMN job.job_search_event.candidate_profile_id IS '[Internal] Searching candidate; null: guest search, session_token identifies it';
COMMENT ON COLUMN job.job_search_event.session_token IS '[Internal] Anonymous session identifier for guests; null: logged-in candidate';
COMMENT ON COLUMN job.job_search_event.search_query IS '[Internal] Keywords typed, max 500; null: filter-only search';
COMMENT ON COLUMN job.job_search_event.search_filters IS '[Internal] Filters applied as JSON; null: keyword-only search';
COMMENT ON COLUMN job.job_search_event.result_count IS '[Internal] Number of jobs returned';
COMMENT ON COLUMN job.job_search_event.searched_at IS '[Internal] Search instant (UTC)';

-- ---------------------------------------------------------------------------------------------------
-- FKs that close cycles or point back from profile (tables now exist)
ALTER TABLE profile.candidate_bookmark_event
  ADD CONSTRAINT fk_candidate_bookmark_event_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT;
ALTER TABLE profile.referral
  ADD CONSTRAINT fk_referral_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT;

-- =====================================================================================================
-- M6: unique and check constraints, pipeline triggers, indexes (job)
-- =====================================================================================================

ALTER TABLE job.job_requirement
  ADD CONSTRAINT ck_job_requirement_salary_range
    CHECK (salary_min IS NULL OR salary_max IS NULL OR salary_min <= salary_max),
  -- RG5: amounts, currency and pay period exist exactly when the salary is disclosed (no 0 / '' sentinels)
  ADD CONSTRAINT ck_job_requirement_salary_disclosure CHECK (
        (salary_disclosure_code = 'disclosed' AND salary_min IS NOT NULL AND currency_code IS NOT NULL AND pay_period_code IS NOT NULL)
     OR (salary_disclosure_code <> 'disclosed' AND salary_min IS NULL AND salary_max IS NULL AND currency_code IS NULL AND pay_period_code IS NULL)),
  ADD CONSTRAINT ck_job_requirement_salary_non_negative CHECK (salary_min >= 0 AND salary_max >= 0),
  ADD CONSTRAINT ck_job_requirement_experience_range
    CHECK (experience_min_months IS NULL OR experience_max_months IS NULL OR experience_min_months <= experience_max_months),
  ADD CONSTRAINT ck_job_requirement_experience_non_negative CHECK (experience_min_months >= 0 AND experience_max_months >= 0),
  ADD CONSTRAINT ck_job_requirement_consultant_fee CHECK (is_open_to_consultant = (consultant_fee_pct IS NOT NULL)),
  ADD CONSTRAINT ck_job_requirement_published_at CHECK (publish_state_code <> 'published' OR published_at IS NOT NULL),
  ADD CONSTRAINT ck_job_requirement_job_title_not_blank CHECK (btrim(job_title) <> ''),
  ADD CONSTRAINT ck_job_requirement_description_not_blank CHECK (btrim(description) <> ''),
  ADD CONSTRAINT ck_job_requirement_legacy_source_pair CHECK ((legacy_source_system IS NULL) = (legacy_source_id IS NULL)),
  ADD CONSTRAINT uq_job_requirement_legacy_source_system_legacy_source_id UNIQUE (legacy_source_system, legacy_source_id);
-- Search surface: open, published, live jobs only (partial index stays small as closed jobs accumulate)
CREATE INDEX idx_job_requirement_open_published ON job.job_requirement (job_role_id, published_at DESC)
  WHERE job_requirement_status_code = 'open' AND publish_state_code = 'published' AND deleted_at IS NULL;
CREATE INDEX idx_job_requirement_organisation_id ON job.job_requirement (organisation_id, job_requirement_status_code);
CREATE INDEX idx_job_requirement_job_title_trgm ON job.job_requirement USING gin (job_title gin_trgm_ops);
CREATE INDEX idx_job_requirement_search_document ON job.job_requirement
  USING gin (to_tsvector('simple'::regconfig, job_title || ' ' || description));

ALTER TABLE job.job_position
  ADD CONSTRAINT uq_job_position_job_requirement_id_position_number UNIQUE (job_requirement_id, position_number),
  ADD CONSTRAINT uq_job_position_filled_by_application_id UNIQUE (filled_by_application_id),
  ADD CONSTRAINT ck_job_position_position_number CHECK (position_number > 0),
  ADD CONSTRAINT ck_job_position_fill_pair CHECK (num_nulls(filled_by_application_id, filled_by_candidate_profile_id, filled_on) IN (0, 3));

ALTER TABLE job.job_requirement_location
  ADD CONSTRAINT uq_job_requirement_location_job_requirement_id_city_id UNIQUE (job_requirement_id, city_id);
CREATE INDEX idx_job_requirement_location_city_id ON job.job_requirement_location (city_id);
ALTER TABLE job.job_requirement_skill
  ADD CONSTRAINT uq_job_requirement_skill_job_requirement_id_skill_id UNIQUE (job_requirement_id, skill_id),
  ADD CONSTRAINT ck_job_requirement_skill_min_experience_months CHECK (min_experience_months >= 0);
CREATE INDEX idx_job_requirement_skill_skill_id ON job.job_requirement_skill (skill_id);
ALTER TABLE job.job_requirement_qualification
  ADD CONSTRAINT uq_job_requirement_qualification_entry
    UNIQUE NULLS NOT DISTINCT (job_requirement_id, qualification_id, field_of_study_id);
ALTER TABLE job.job_requirement_questionnaire
  ADD CONSTRAINT uq_job_requirement_questionnaire_pair UNIQUE (job_requirement_id, questionnaire_id);

ALTER TABLE job.questionnaire
  ADD CONSTRAINT uq_questionnaire_organisation_id_questionnaire_title UNIQUE (organisation_id, questionnaire_title);
ALTER TABLE job.questionnaire_question
  ADD CONSTRAINT uq_questionnaire_question_questionnaire_id_question_order UNIQUE (questionnaire_id, question_order),
  ADD CONSTRAINT ck_questionnaire_question_question_order CHECK (question_order > 0);
ALTER TABLE job.question_option
  ADD CONSTRAINT uq_question_option_questionnaire_question_id_option_order UNIQUE (questionnaire_question_id, option_order),
  ADD CONSTRAINT ck_question_option_option_order CHECK (option_order > 0);

ALTER TABLE job.application
  ADD CONSTRAINT uq_application_candidate_profile_id_job_requirement_id UNIQUE (candidate_profile_id, job_requirement_id),
  ADD CONSTRAINT uq_application_id_candidate_profile_id_job_requirement_id UNIQUE (id, candidate_profile_id, job_requirement_id),
  ADD CONSTRAINT ck_application_rejection_reason
    CHECK ((application_status_code = 'rejected') = (rejection_reason_code IS NOT NULL)),
  ADD CONSTRAINT ck_application_status_changed_at CHECK (status_changed_at >= applied_at);
CREATE INDEX idx_application_job_requirement_id ON job.application (job_requirement_id, application_status_code);

-- An opening can only be filled by an application to the same requirement
ALTER TABLE job.job_position
  ADD CONSTRAINT fk_job_position_filled_by_application
    FOREIGN KEY (filled_by_application_id, filled_by_candidate_profile_id, job_requirement_id)
    REFERENCES job.application (id, candidate_profile_id, job_requirement_id)
    ON UPDATE NO ACTION ON DELETE RESTRICT;

ALTER TABLE job.application_answer
  ADD CONSTRAINT uq_application_answer_application_question_option
    UNIQUE NULLS NOT DISTINCT (application_id, questionnaire_question_id, question_option_id),
  ADD CONSTRAINT ck_application_answer_single_kind CHECK (num_nonnulls(question_option_id, answer_text, answer_number) = 1);

CREATE INDEX idx_application_status_history_application_id ON job.application_status_history (application_id, changed_at);

ALTER TABLE job.application_status_transition
  ADD CONSTRAINT uq_application_status_transition_from_to UNIQUE (from_application_status_code, to_application_status_code),
  ADD CONSTRAINT ck_application_status_transition_not_self CHECK (from_application_status_code <> to_application_status_code);

ALTER TABLE job.shortlist
  ADD CONSTRAINT uq_shortlist_organisation_id_shortlist_name UNIQUE (organisation_id, shortlist_name);
CREATE UNIQUE INDEX uq_shortlist_entry_shortlist_id_candidate_profile_id
  ON job.shortlist_entry (shortlist_id, candidate_profile_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_shortlist_entry_candidate_profile_id ON job.shortlist_entry (candidate_profile_id);

ALTER TABLE job.interview
  ADD CONSTRAINT uq_interview_application_id_round_number UNIQUE (application_id, round_number),
  ADD CONSTRAINT ck_interview_round_number CHECK (round_number > 0),
  ADD CONSTRAINT ck_interview_schedule CHECK (scheduled_end > scheduled_start),
  ADD CONSTRAINT ck_interview_outcome CHECK (interview_outcome_code IS NULL OR interview_status_code = 'completed'),
  ADD CONSTRAINT ck_interview_venue_by_mode CHECK (interview_mode_code <> 'in_person' OR venue IS NOT NULL);

ALTER TABLE job.offer
  ADD CONSTRAINT uq_offer_id_application_id UNIQUE (id, application_id),
  ADD CONSTRAINT ck_offer_ctc_amount CHECK (ctc_amount > 0),
  ADD CONSTRAINT ck_offer_valid_until CHECK (valid_until IS NULL OR valid_until >= offered_on),
  ADD CONSTRAINT ck_offer_proposed_joining_date CHECK (proposed_joining_date IS NULL OR proposed_joining_date >= offered_on);
CREATE INDEX idx_offer_application_id ON job.offer (application_id);

ALTER TABLE job.joining
  ADD CONSTRAINT uq_joining_application_id UNIQUE (application_id),
  ADD CONSTRAINT uq_joining_offer_id UNIQUE (offer_id),
  -- the joining's offer must belong to the same application
  ADD CONSTRAINT fk_joining_offer_id_application_id FOREIGN KEY (offer_id, application_id) REFERENCES job.offer (id, application_id)
    ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT ck_joining_actual_date CHECK ((joining_status_code = 'joined') = (actual_joining_date IS NOT NULL));

ALTER TABLE job.saved_search
  ADD CONSTRAINT uq_saved_search_candidate_profile_id_search_name UNIQUE (candidate_profile_id, search_name);

ALTER TABLE job.job_search_event
  ADD CONSTRAINT ck_job_search_event_searcher CHECK (num_nonnulls(candidate_profile_id, session_token) = 1),
  ADD CONSTRAINT ck_job_search_event_result_count CHECK (result_count >= 0);
CREATE INDEX idx_job_search_event_candidate_profile_id ON job.job_search_event (candidate_profile_id, searched_at)
  WHERE candidate_profile_id IS NOT NULL;

-- ---------------------------------------------------------------------------------------------------
-- Pipeline rules (B22): legal transitions only, and every change lands in the append-only history.
--   BEFORE trigger: a new application starts as 'applied' on an open, published, live job (imported legacy
--                   applications are exempt); a status change must be listed in application_status_transition.
--   AFTER trigger:  writes application_status_history (actor = created_by; optional reason from
--                   SET LOCAL app.status_change_reason).
CREATE FUNCTION job.enforce_application_status_transition() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.application_source_code <> 'imported' THEN
      IF NEW.application_status_code <> 'applied' THEN
        RAISE EXCEPTION 'trg_application_status_transition: a new application must start as applied, not %',
                        NEW.application_status_code USING ERRCODE = 'check_violation';
      END IF;
      IF NOT EXISTS (SELECT 1
                       FROM job.job_requirement jr
                       JOIN ref.job_requirement_status s ON s.code = jr.job_requirement_status_code
                      WHERE jr.id = NEW.job_requirement_id AND s.accepts_applications
                        AND jr.publish_state_code = 'published' AND jr.deleted_at IS NULL) THEN
        RAISE EXCEPTION 'trg_application_status_transition: job requirement % is not open and published',
                        NEW.job_requirement_id USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    NEW.status_changed_at := NEW.applied_at;
  ELSIF NEW.application_status_code IS DISTINCT FROM OLD.application_status_code THEN
    IF NOT EXISTS (SELECT 1 FROM job.application_status_transition t
                    WHERE t.from_application_status_code = OLD.application_status_code
                      AND t.to_application_status_code = NEW.application_status_code
                      AND t.is_active) THEN
      RAISE EXCEPTION 'trg_application_status_transition: transition % -> % not allowed',
                      OLD.application_status_code, NEW.application_status_code USING ERRCODE = 'check_violation';
    END IF;
    NEW.status_changed_at := now();
  END IF;
  RETURN NEW;
END
$$;

CREATE FUNCTION job.record_application_status_history() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.application_status_code IS DISTINCT FROM OLD.application_status_code THEN
    INSERT INTO job.application_status_history
           (application_id, candidate_profile_id, from_application_status_code, to_application_status_code, changed_at, change_reason)
    VALUES (NEW.id, NEW.candidate_profile_id,
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.application_status_code END,
            NEW.application_status_code,
            NEW.status_changed_at,
            nullif(current_setting('app.status_change_reason', true), ''));
  END IF;
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_application_status_transition
  BEFORE INSERT OR UPDATE OF application_status_code ON job.application
  FOR EACH ROW EXECUTE FUNCTION job.enforce_application_status_transition();
CREATE TRIGGER trg_application_status_history
  AFTER INSERT OR UPDATE OF application_status_code ON job.application
  FOR EACH ROW EXECUTE FUNCTION job.record_application_status_history();
