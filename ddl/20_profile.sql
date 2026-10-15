-- Profile (schema profile). Owner A. Entities and relationships: docs/phase1/entities.md, relationships.md.
--   M4: columns, PKs and FKs (ON DELETE as in relationships.md).
--   M6: unique / check constraints, indexes (appended below in the M6 section).
-- FKs to job.* (bookmark and referral -> job_requirement) are added in ddl/30_jobs.sql once those tables exist.
-- Contact details are Personal: protected by RLS and masking views (M18, M22), not encrypted, because they are
-- searched and de-duplicated; national identifiers are Sensitive and never stored in clear (token + hash + last 4).

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_profile (
  id                               bigint GENERATED ALWAYS AS IDENTITY,
  app_user_id                      bigint        NOT NULL,
  full_name                        d_person_name NOT NULL,
  given_name                       d_person_name,
  family_name                      d_person_name,
  date_of_birth                    date,
  gender_code                      d_code,
  nationality_country_id           bigint,
  current_city_id                  bigint,
  headline                         varchar(250),
  summary                          varchar(4000),
  summary_language_id              bigint,
  total_experience_months          integer,
  current_salary_disclosure_code   d_code        NOT NULL DEFAULT 'not_disclosed',
  current_salary_amount            d_money,
  expected_salary_disclosure_code  d_code        NOT NULL DEFAULT 'not_disclosed',
  expected_salary_amount           d_money,
  currency_code                    d_currency_code,
  pay_period_code                  d_code,
  notice_period_code               d_code,
  is_open_to_work                  boolean       NOT NULL DEFAULT true,
  legacy_source_system             varchar(30),
  legacy_source_id                 varchar(64),
  created_at                       timestamptz   NOT NULL DEFAULT now(),
  created_by                       bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at                       timestamptz   NOT NULL DEFAULT now(),
  updated_by                       bigint        NOT NULL DEFAULT public.current_actor_id(),
  deleted_at                       timestamptz,
  CONSTRAINT pk_candidate_profile PRIMARY KEY (id),
  CONSTRAINT fk_candidate_profile_app_user_id FOREIGN KEY (app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_gender_code FOREIGN KEY (gender_code) REFERENCES ref.gender (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_nationality_country_id FOREIGN KEY (nationality_country_id) REFERENCES ref.country (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_current_city_id FOREIGN KEY (current_city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_summary_language_id FOREIGN KEY (summary_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_current_salary_disclosure_code FOREIGN KEY (current_salary_disclosure_code) REFERENCES ref.disclosure (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_expected_salary_disclosure_code FOREIGN KEY (expected_salary_disclosure_code) REFERENCES ref.disclosure (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_currency_code FOREIGN KEY (currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_pay_period_code FOREIGN KEY (pay_period_code) REFERENCES ref.pay_period (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_profile_notice_period_code FOREIGN KEY (notice_period_code) REFERENCES ref.notice_period (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_profile IS '[soft-delete] Candidate personal details, headline, summary, experience and salary with disclosure; 1:1 with app_user. Retention: anonymised and purged 30 days after a deletion request, or after 36 months of inactivity';
COMMENT ON COLUMN profile.candidate_profile.app_user_id IS '[Internal] Login identity that owns the profile (unique)';
COMMENT ON COLUMN profile.candidate_profile.full_name IS '[Personal] Name as the candidate writes it, any script or order';
COMMENT ON COLUMN profile.candidate_profile.given_name IS '[Personal] Given name for formal letters; null: single-name person or not split';
COMMENT ON COLUMN profile.candidate_profile.family_name IS '[Personal] Family name; null: single-name person or not split';
COMMENT ON COLUMN profile.candidate_profile.date_of_birth IS '[Personal] Date of birth; null: not provided (optional for most job categories)';
COMMENT ON COLUMN profile.candidate_profile.gender_code IS '[Personal] Self-described gender; null: never asked or not entered (an explicit refusal is prefer_not_to_say)';
COMMENT ON COLUMN profile.candidate_profile.nationality_country_id IS '[Personal] Nationality; null: not provided';
COMMENT ON COLUMN profile.candidate_profile.current_city_id IS '[Personal] City the candidate lives in; null: not provided';
COMMENT ON COLUMN profile.candidate_profile.headline IS '[Personal] One-line professional headline, max 250; null: not written yet';
COMMENT ON COLUMN profile.candidate_profile.summary IS '[Personal] Profile summary, max 4000; null: not written yet';
COMMENT ON COLUMN profile.candidate_profile.summary_language_id IS '[Internal] Language of summary; null: no summary or language not detected (RG7)';
COMMENT ON COLUMN profile.candidate_profile.total_experience_months IS '[Personal] Total experience in months (0 = fresher); null: not provided';
COMMENT ON COLUMN profile.candidate_profile.current_salary_disclosure_code IS '[Personal] disclosed / not_disclosed / not_applicable (not employed); default not_disclosed';
COMMENT ON COLUMN profile.candidate_profile.current_salary_amount IS '[Personal] Current salary; null: not disclosed or not applicable (see disclosure code, CHECK in M6)';
COMMENT ON COLUMN profile.candidate_profile.expected_salary_disclosure_code IS '[Personal] disclosed / not_disclosed / not_applicable; default not_disclosed';
COMMENT ON COLUMN profile.candidate_profile.expected_salary_amount IS '[Personal] Expected salary; null: not disclosed or not applicable';
COMMENT ON COLUMN profile.candidate_profile.currency_code IS '[Personal] Currency of both salary amounts; null: neither salary disclosed';
COMMENT ON COLUMN profile.candidate_profile.pay_period_code IS '[Personal] Period both salary amounts are quoted in; null: neither salary disclosed';
COMMENT ON COLUMN profile.candidate_profile.notice_period_code IS '[Personal] Notice period to serve; null: not currently employed (not applicable)';
COMMENT ON COLUMN profile.candidate_profile.is_open_to_work IS '[Personal] Candidate is looking for work; default true';
COMMENT ON COLUMN profile.candidate_profile.legacy_source_system IS '[Internal] Legacy system the profile was migrated from; null: created natively on Talentra';
COMMENT ON COLUMN profile.candidate_profile.legacy_source_id IS '[Internal] Record id in the legacy system (natural key, unique with the system); nofk: external identifier; null: created natively';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_contact (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint       NOT NULL,
  contact_type_code     d_code       NOT NULL,
  email                 d_email,
  phone                 d_phone_e164,
  phone_country_id      bigint,
  is_primary            boolean      NOT NULL DEFAULT false,
  is_verified           boolean      NOT NULL DEFAULT false,
  verified_at           timestamptz,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_contact PRIMARY KEY (id),
  CONSTRAINT fk_candidate_contact_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_contact_contact_type_code FOREIGN KEY (contact_type_code) REFERENCES ref.contact_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_contact_phone_country_id FOREIGN KEY (phone_country_id) REFERENCES ref.country (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_contact IS '[hard-delete] Email, phone and WhatsApp contact points of a candidate (owned by the profile)';
COMMENT ON COLUMN profile.candidate_contact.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_contact.contact_type_code IS '[Internal] email, phone or whatsapp; decides which value column is filled (CHECK in M6)';
COMMENT ON COLUMN profile.candidate_contact.email IS '[Personal] Lowercase email; null: contact is a phone or WhatsApp number';
COMMENT ON COLUMN profile.candidate_contact.phone IS '[Personal] E.164 number; null: contact is an email';
COMMENT ON COLUMN profile.candidate_contact.phone_country_id IS '[Personal] Country of the phone number; null: contact is an email';
COMMENT ON COLUMN profile.candidate_contact.is_primary IS '[Internal] Primary contact of its type; default false';
COMMENT ON COLUMN profile.candidate_contact.is_verified IS '[Internal] Ownership confirmed by OTP or link; default false';
COMMENT ON COLUMN profile.candidate_contact.verified_at IS '[Internal] When ownership was confirmed; null: not verified yet';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_address (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint       NOT NULL,
  address_type_code     d_code       NOT NULL,
  address_line1         varchar(200) NOT NULL,
  address_line2         varchar(200),
  locality              varchar(100),
  city_id               bigint       NOT NULL,
  postal_code           varchar(12),
  latitude              d_lat,
  longitude             d_lng,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_address PRIMARY KEY (id),
  CONSTRAINT fk_candidate_address_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_address_address_type_code FOREIGN KEY (address_type_code) REFERENCES ref.address_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_address_city_id FOREIGN KEY (city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_address IS '[hard-delete] Candidate address (owned by the profile)';
COMMENT ON COLUMN profile.candidate_address.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_address.address_type_code IS '[Internal] current, permanent or correspondence';
COMMENT ON COLUMN profile.candidate_address.address_line1 IS '[Personal] First address line, max 200';
COMMENT ON COLUMN profile.candidate_address.address_line2 IS '[Personal] Second address line; null: address fits on one line';
COMMENT ON COLUMN profile.candidate_address.locality IS '[Personal] Area or neighbourhood; null: not provided';
COMMENT ON COLUMN profile.candidate_address.city_id IS '[Personal] City (implies state and country)';
COMMENT ON COLUMN profile.candidate_address.postal_code IS '[Personal] Postal or PIN code as text (leading zeros, letters); nofk: free text, no postal master list; null: country without postal codes or not provided';
COMMENT ON COLUMN profile.candidate_address.latitude IS '[Personal] WGS84, 6 dp, source: mapping service geocode of the address; null: not geocoded (optional boundary)';
COMMENT ON COLUMN profile.candidate_address.longitude IS '[Personal] WGS84, 6 dp, source: mapping service geocode of the address; null: not geocoded (optional boundary)';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_identity_document (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id      bigint       NOT NULL,
  identifier_type_code      d_code       NOT NULL,
  verification_token        varchar(128) NOT NULL,
  identifier_hash           bytea        NOT NULL,
  identifier_last4          varchar(4)   NOT NULL,
  verification_status_code  d_code       NOT NULL DEFAULT 'pending',
  verified_at               timestamptz,
  created_at                timestamptz  NOT NULL DEFAULT now(),
  created_by                bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz  NOT NULL DEFAULT now(),
  updated_by                bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_identity_document PRIMARY KEY (id),
  CONSTRAINT fk_candidate_identity_document_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_identity_document_identifier_type_code FOREIGN KEY (identifier_type_code) REFERENCES ref.identifier_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_identity_document_verification_status_code FOREIGN KEY (verification_status_code) REFERENCES ref.verification_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_identity_document IS '[hard-delete] National identifier reference from the identity verification service; the raw number is never stored (docket Section 6)';
COMMENT ON COLUMN profile.candidate_identity_document.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_identity_document.identifier_type_code IS '[Internal] aadhaar, pan, passport ...';
COMMENT ON COLUMN profile.candidate_identity_document.verification_token IS '[Sensitive] Opaque token returned by the verification service, used for re-checks';
COMMENT ON COLUMN profile.candidate_identity_document.identifier_hash IS '[Sensitive] HMAC-SHA256 of the normalised number with a key held outside the database; detects duplicates without storing the number';
COMMENT ON COLUMN profile.candidate_identity_document.identifier_last4 IS '[Sensitive] Last 4 characters for masked display (XXXX-XXXX-1234)';
COMMENT ON COLUMN profile.candidate_identity_document.verification_status_code IS '[Internal] Outcome from the verification service; default pending';
COMMENT ON COLUMN profile.candidate_identity_document.verified_at IS '[Internal] When the service confirmed the identifier; null: not verified yet';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_language (
  id                      bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id    bigint      NOT NULL,
  language_id             bigint      NOT NULL,
  proficiency_level_code  d_code      NOT NULL,
  can_read                boolean     NOT NULL DEFAULT true,
  can_write               boolean     NOT NULL DEFAULT true,
  can_speak               boolean     NOT NULL DEFAULT true,
  created_at              timestamptz NOT NULL DEFAULT now(),
  created_by              bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  updated_by              bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_language PRIMARY KEY (id),
  CONSTRAINT fk_candidate_language_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_language_language_id FOREIGN KEY (language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_language_proficiency_level_code FOREIGN KEY (proficiency_level_code) REFERENCES ref.proficiency_level (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_language IS '[hard-delete] Languages a candidate knows (junction, owned by the profile)';
COMMENT ON COLUMN profile.candidate_language.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_language.language_id IS '[Personal] Language known';
COMMENT ON COLUMN profile.candidate_language.proficiency_level_code IS '[Personal] Overall proficiency';
COMMENT ON COLUMN profile.candidate_language.can_read IS '[Personal] Reads the language; default true';
COMMENT ON COLUMN profile.candidate_language.can_write IS '[Personal] Writes the language; default true';
COMMENT ON COLUMN profile.candidate_language.can_speak IS '[Personal] Speaks the language; default true';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_education (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint       NOT NULL,
  qualification_id      bigint       NOT NULL,
  field_of_study_id     bigint,
  institution_id        bigint,
  institution_name      varchar(250),
  study_mode_code       d_code,
  start_date            date         NOT NULL,
  end_date              date,
  score_pct             d_pct,
  grade_text            varchar(20),
  is_highest            boolean      NOT NULL DEFAULT false,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_education PRIMARY KEY (id),
  CONSTRAINT fk_candidate_education_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_education_qualification_id FOREIGN KEY (qualification_id) REFERENCES ref.qualification (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_education_field_of_study_id FOREIGN KEY (field_of_study_id) REFERENCES ref.field_of_study (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_education_institution_id FOREIGN KEY (institution_id) REFERENCES ref.institution (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_education_study_mode_code FOREIGN KEY (study_mode_code) REFERENCES ref.study_mode (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_education IS '[hard-delete] Education history entry (owned by the profile)';
COMMENT ON COLUMN profile.candidate_education.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_education.qualification_id IS '[Personal] Qualification studied';
COMMENT ON COLUMN profile.candidate_education.field_of_study_id IS '[Personal] Specialisation; null: qualification has no specialisation (secondary school)';
COMMENT ON COLUMN profile.candidate_education.institution_id IS '[Personal] Institution from the master list; null: not in the list, institution_name is used (CHECK in M6)';
COMMENT ON COLUMN profile.candidate_education.institution_name IS '[Personal] Institution as typed, max 250; null: institution_id is set';
COMMENT ON COLUMN profile.candidate_education.study_mode_code IS '[Personal] Full time, part time ...; null: not provided';
COMMENT ON COLUMN profile.candidate_education.start_date IS '[Personal] Start of the course';
COMMENT ON COLUMN profile.candidate_education.end_date IS '[Personal] Completion date; null: still studying';
COMMENT ON COLUMN profile.candidate_education.score_pct IS '[Personal] Score as a percentage 0-100; null: not disclosed or graded on another scale (grade_text)';
COMMENT ON COLUMN profile.candidate_education.grade_text IS '[Personal] Grade on a non-percentage scale (8.6 CGPA, First Class); null: score_pct used or not disclosed';
COMMENT ON COLUMN profile.candidate_education.is_highest IS '[Personal] Highest qualification of the candidate; default false';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_work_experience (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id     bigint       NOT NULL,
  organisation_id          bigint,
  employer_name            varchar(200),
  designation              varchar(150) NOT NULL,
  job_role_id              bigint,
  industry_id              bigint,
  employment_type_code     d_code       NOT NULL,
  city_id                  bigint,
  start_date               date         NOT NULL,
  end_date                 date,
  is_current               boolean      NOT NULL DEFAULT false,
  description              varchar(4000),
  description_language_id  bigint,
  created_at               timestamptz  NOT NULL DEFAULT now(),
  created_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz  NOT NULL DEFAULT now(),
  updated_by               bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_work_experience PRIMARY KEY (id),
  CONSTRAINT fk_candidate_work_experience_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_work_experience_organisation_id FOREIGN KEY (organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_work_experience_job_role_id FOREIGN KEY (job_role_id) REFERENCES ref.job_role (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_work_experience_industry_id FOREIGN KEY (industry_id) REFERENCES ref.industry (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_work_experience_employment_type_code FOREIGN KEY (employment_type_code) REFERENCES ref.employment_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_work_experience_city_id FOREIGN KEY (city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_work_experience_description_language_id FOREIGN KEY (description_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_work_experience IS '[hard-delete] Employment history entry (owned by the profile)';
COMMENT ON COLUMN profile.candidate_work_experience.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_work_experience.organisation_id IS '[Personal] Employer registered on Talentra; null: not registered, employer_name is used (CHECK in M6)';
COMMENT ON COLUMN profile.candidate_work_experience.employer_name IS '[Personal] Employer as typed, max 200; null: organisation_id is set';
COMMENT ON COLUMN profile.candidate_work_experience.designation IS '[Personal] Job title as held, max 150';
COMMENT ON COLUMN profile.candidate_work_experience.job_role_id IS '[Personal] Standard role mapped from the designation; null: not mapped yet';
COMMENT ON COLUMN profile.candidate_work_experience.industry_id IS '[Personal] Industry of the employer; null: not provided';
COMMENT ON COLUMN profile.candidate_work_experience.employment_type_code IS '[Personal] Permanent, contract, internship ...';
COMMENT ON COLUMN profile.candidate_work_experience.city_id IS '[Personal] Work location; null: remote role or not provided';
COMMENT ON COLUMN profile.candidate_work_experience.start_date IS '[Personal] Start date';
COMMENT ON COLUMN profile.candidate_work_experience.end_date IS '[Personal] End date; null: current job';
COMMENT ON COLUMN profile.candidate_work_experience.is_current IS '[Personal] Candidate still works here; default false';
COMMENT ON COLUMN profile.candidate_work_experience.description IS '[Personal] Responsibilities and achievements, max 4000; null: not written';
COMMENT ON COLUMN profile.candidate_work_experience.description_language_id IS '[Internal] Language of description; null: no description or not detected';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_skill (
  id                      bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id    bigint      NOT NULL,
  skill_id                bigint      NOT NULL,
  proficiency_level_code  d_code,
  experience_months       integer,
  last_used_year          smallint,
  created_at              timestamptz NOT NULL DEFAULT now(),
  created_by              bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  updated_by              bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_skill PRIMARY KEY (id),
  CONSTRAINT fk_candidate_skill_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_skill_skill_id FOREIGN KEY (skill_id) REFERENCES ref.skill (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_skill_proficiency_level_code FOREIGN KEY (proficiency_level_code) REFERENCES ref.proficiency_level (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_skill IS '[hard-delete] Candidate-to-skill junction (owned by the profile)';
COMMENT ON COLUMN profile.candidate_skill.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_skill.skill_id IS '[Personal] Skill held';
COMMENT ON COLUMN profile.candidate_skill.proficiency_level_code IS '[Personal] Self-rated proficiency; null: candidate did not self-rate';
COMMENT ON COLUMN profile.candidate_skill.experience_months IS '[Personal] Months of use; null: not provided';
COMMENT ON COLUMN profile.candidate_skill.last_used_year IS '[Personal] Year last used; null: not provided';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_certification (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint       NOT NULL,
  certification_name    varchar(200) NOT NULL,
  issuing_body          varchar(200) NOT NULL,
  skill_id              bigint,
  issue_date            date         NOT NULL,
  expiry_date           date,
  credential_reference  varchar(100),
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_certification PRIMARY KEY (id),
  CONSTRAINT fk_candidate_certification_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_certification_skill_id FOREIGN KEY (skill_id) REFERENCES ref.skill (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_certification IS '[hard-delete] Certification held by a candidate (owned by the profile)';
COMMENT ON COLUMN profile.candidate_certification.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_certification.certification_name IS '[Personal] Certification title, max 200';
COMMENT ON COLUMN profile.candidate_certification.issuing_body IS '[Personal] Issuer (AWS, NSDC), max 200';
COMMENT ON COLUMN profile.candidate_certification.skill_id IS '[Personal] Skill certified; null: certification not tied to one skill';
COMMENT ON COLUMN profile.candidate_certification.issue_date IS '[Personal] Date issued';
COMMENT ON COLUMN profile.candidate_certification.expiry_date IS '[Personal] Expiry date; null: does not expire';
COMMENT ON COLUMN profile.candidate_certification.credential_reference IS '[Personal] Credential number printed on the certificate; null: issuer gives none';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_project (
  id                            bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id          bigint       NOT NULL,
  project_kind_code             d_code       NOT NULL,
  project_title                 varchar(200) NOT NULL,
  candidate_work_experience_id  bigint,
  project_role                  varchar(150),
  start_date                    date         NOT NULL,
  end_date                      date,
  outcome                       varchar(1000),
  description                   varchar(4000),
  description_language_id      bigint,
  project_url                   varchar(500),
  created_at                    timestamptz  NOT NULL DEFAULT now(),
  created_by                    bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at                    timestamptz  NOT NULL DEFAULT now(),
  updated_by                    bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_project PRIMARY KEY (id),
  CONSTRAINT fk_candidate_project_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_project_project_kind_code FOREIGN KEY (project_kind_code) REFERENCES ref.project_kind (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_project_candidate_work_experience_id FOREIGN KEY (candidate_work_experience_id) REFERENCES profile.candidate_work_experience (id) ON UPDATE NO ACTION ON DELETE SET NULL,
  CONSTRAINT fk_candidate_project_description_language_id FOREIGN KEY (description_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_project IS '[hard-delete] Candidate or gig project with role, duration and outcome (owned by the profile)';
COMMENT ON COLUMN profile.candidate_project.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_project.project_kind_code IS '[Personal] employment, academic, personal or gig';
COMMENT ON COLUMN profile.candidate_project.project_title IS '[Personal] Project name, max 200';
COMMENT ON COLUMN profile.candidate_project.candidate_work_experience_id IS '[Personal] Job the project was done in; null: not done in a listed job';
COMMENT ON COLUMN profile.candidate_project.project_role IS '[Personal] Role on the project, max 150; null: not provided';
COMMENT ON COLUMN profile.candidate_project.start_date IS '[Personal] Start date';
COMMENT ON COLUMN profile.candidate_project.end_date IS '[Personal] End date; null: ongoing';
COMMENT ON COLUMN profile.candidate_project.outcome IS '[Personal] Result achieved, max 1000; null: not written';
COMMENT ON COLUMN profile.candidate_project.description IS '[Personal] Description, max 4000; null: not written';
COMMENT ON COLUMN profile.candidate_project.description_language_id IS '[Internal] Language of description; null: no description or not detected';
COMMENT ON COLUMN profile.candidate_project.project_url IS '[Personal] Public link to the work, max 500; null: none';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_preferred_location (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint      NOT NULL,
  city_id               bigint      NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  created_by            bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_preferred_location PRIMARY KEY (id),
  CONSTRAINT fk_candidate_preferred_location_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_preferred_location_city_id FOREIGN KEY (city_id) REFERENCES ref.city (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_preferred_location IS '[hard-delete] City a candidate wants to work in (junction, owned by the profile)';
COMMENT ON COLUMN profile.candidate_preferred_location.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_preferred_location.city_id IS '[Personal] Preferred city';

CREATE TABLE profile.candidate_preferred_role (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint      NOT NULL,
  job_role_id           bigint      NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  created_by            bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_preferred_role PRIMARY KEY (id),
  CONSTRAINT fk_candidate_preferred_role_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_preferred_role_job_role_id FOREIGN KEY (job_role_id) REFERENCES ref.job_role (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_preferred_role IS '[hard-delete] Job role a candidate is looking for (junction, owned by the profile)';
COMMENT ON COLUMN profile.candidate_preferred_role.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_preferred_role.job_role_id IS '[Personal] Preferred role';

CREATE TABLE profile.candidate_web_link (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint       NOT NULL,
  web_link_type_code    d_code       NOT NULL,
  link_url              varchar(500) NOT NULL,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_web_link PRIMARY KEY (id),
  CONSTRAINT fk_candidate_web_link_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_candidate_web_link_web_link_type_code FOREIGN KEY (web_link_type_code) REFERENCES ref.web_link_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_web_link IS '[hard-delete] External profile link (owned by the profile)';
COMMENT ON COLUMN profile.candidate_web_link.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.candidate_web_link.web_link_type_code IS '[Internal] linkedin, github, portfolio, other';
COMMENT ON COLUMN profile.candidate_web_link.link_url IS '[Personal] URL, max 500';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.resume_template (
  id                 bigint GENERATED ALWAYS AS IDENTITY,
  template_name      varchar(100) NOT NULL,
  language_id        bigint       NOT NULL,
  layout_definition  jsonb        NOT NULL,
  is_active          boolean      NOT NULL DEFAULT true,
  created_at         timestamptz  NOT NULL DEFAULT now(),
  created_by         bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at         timestamptz  NOT NULL DEFAULT now(),
  updated_by         bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_resume_template PRIMARY KEY (id),
  CONSTRAINT fk_resume_template_language_id FOREIGN KEY (language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.resume_template IS '[hard-delete] Platform resume layout candidates build from';
COMMENT ON COLUMN profile.resume_template.template_name IS '[Public] Template name, max 100';
COMMENT ON COLUMN profile.resume_template.language_id IS '[Public] Language of the fixed headings';
COMMENT ON COLUMN profile.resume_template.layout_definition IS '[Public] Section order and styling as JSON (renderer contract)';
COMMENT ON COLUMN profile.resume_template.is_active IS '[Public] Offered to candidates; default true';

CREATE TABLE profile.resume_version (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint       NOT NULL,
  resume_template_id    bigint,
  version_number        integer      NOT NULL,
  version_label         varchar(100),
  body                  text,
  body_language_id      bigint,
  file_storage_key      varchar(500),
  file_mime_type        varchar(100),
  file_size_bytes       bigint,
  is_default            boolean      NOT NULL DEFAULT false,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  deleted_at            timestamptz,
  CONSTRAINT pk_resume_version PRIMARY KEY (id),
  CONSTRAINT fk_resume_version_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_resume_version_resume_template_id FOREIGN KEY (resume_template_id) REFERENCES profile.resume_template (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_resume_version_body_language_id FOREIGN KEY (body_language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.resume_version IS '[soft-delete] A saved resume, built from a template or uploaded (owned by the profile)';
COMMENT ON COLUMN profile.resume_version.candidate_profile_id IS '[Internal] Owning profile';
COMMENT ON COLUMN profile.resume_version.resume_template_id IS '[Internal] Template used; null: uploaded file, not built from a template';
COMMENT ON COLUMN profile.resume_version.version_number IS '[Internal] 1, 2, 3 ... per profile (unique in M6)';
COMMENT ON COLUMN profile.resume_version.version_label IS '[Personal] Candidate label (Backend roles); null: unnamed';
COMMENT ON COLUMN profile.resume_version.body IS '[Personal] Resume text; unbounded: resume bodies are free-form documents of unpredictable length (docket allows it); null: uploaded file whose text is not extracted yet';
COMMENT ON COLUMN profile.resume_version.body_language_id IS '[Internal] Language of body as entered or detected; null: no body or not detected (RG7)';
COMMENT ON COLUMN profile.resume_version.file_storage_key IS '[Personal] Object-store key of the uploaded file; null: built resume, no file';
COMMENT ON COLUMN profile.resume_version.file_mime_type IS '[Internal] MIME type of the file; null: no file';
COMMENT ON COLUMN profile.resume_version.file_size_bytes IS '[Internal] File size; null: no file';
COMMENT ON COLUMN profile.resume_version.is_default IS '[Internal] Resume attached by default when applying; default false';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE profile.assessment (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  assessment_name       varchar(200) NOT NULL,
  assessment_type_code  d_code       NOT NULL,
  skill_id              bigint,
  max_score             numeric(7,2) NOT NULL,
  duration_minutes      smallint,
  is_active             boolean      NOT NULL DEFAULT true,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz  NOT NULL DEFAULT now(),
  updated_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_assessment PRIMARY KEY (id),
  CONSTRAINT fk_assessment_assessment_type_code FOREIGN KEY (assessment_type_code) REFERENCES ref.assessment_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_assessment_skill_id FOREIGN KEY (skill_id) REFERENCES ref.skill (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.assessment IS '[hard-delete] Assessment catalogue entry';
COMMENT ON COLUMN profile.assessment.assessment_name IS '[Public] Name, max 200';
COMMENT ON COLUMN profile.assessment.assessment_type_code IS '[Public] self_assessment, skill_test, aptitude, language';
COMMENT ON COLUMN profile.assessment.skill_id IS '[Public] Skill assessed; null: general aptitude, not skill-specific';
COMMENT ON COLUMN profile.assessment.max_score IS '[Public] Highest possible raw score';
COMMENT ON COLUMN profile.assessment.duration_minutes IS '[Public] Time limit; null: untimed';
COMMENT ON COLUMN profile.assessment.is_active IS '[Public] Offered to candidates; default true';

CREATE TABLE profile.assessment_attempt (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  assessment_id         bigint       NOT NULL,
  candidate_profile_id  bigint       NOT NULL,
  started_at            timestamptz  NOT NULL,
  submitted_at          timestamptz  NOT NULL,
  raw_score             numeric(7,2) NOT NULL,
  score_pct             d_pct        NOT NULL,
  percentile_pct        d_pct,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  created_by            bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_assessment_attempt PRIMARY KEY (id),
  CONSTRAINT fk_assessment_attempt_assessment_id FOREIGN KEY (assessment_id) REFERENCES profile.assessment (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_assessment_attempt_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.assessment_attempt IS '[append-only] One submitted assessment attempt with its score; abandoned attempts are not recorded';
COMMENT ON COLUMN profile.assessment_attempt.assessment_id IS '[Internal] Assessment taken';
COMMENT ON COLUMN profile.assessment_attempt.candidate_profile_id IS '[Internal] Candidate who took it';
COMMENT ON COLUMN profile.assessment_attempt.started_at IS '[Personal] Attempt start (UTC)';
COMMENT ON COLUMN profile.assessment_attempt.submitted_at IS '[Personal] Attempt submission (UTC)';
COMMENT ON COLUMN profile.assessment_attempt.raw_score IS '[Personal] Raw score (0 to assessment.max_score)';
COMMENT ON COLUMN profile.assessment_attempt.score_pct IS '[Personal] raw_score / max_score as a percentage';
COMMENT ON COLUMN profile.assessment_attempt.percentile_pct IS '[Personal] Percentile among all attempts; null: too few attempts to rank (computed nightly)';

CREATE TABLE profile.course (
  id              bigint GENERATED ALWAYS AS IDENTITY,
  course_title    varchar(200) NOT NULL,
  provider_name   varchar(150) NOT NULL,
  skill_id        bigint,
  course_url      varchar(500),
  duration_hours  smallint,
  is_active       boolean      NOT NULL DEFAULT true,
  created_at      timestamptz  NOT NULL DEFAULT now(),
  created_by      bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at      timestamptz  NOT NULL DEFAULT now(),
  updated_by      bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_course PRIMARY KEY (id),
  CONSTRAINT fk_course_skill_id FOREIGN KEY (skill_id) REFERENCES ref.skill (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.course IS '[hard-delete] Course catalogue entry';
COMMENT ON COLUMN profile.course.course_title IS '[Public] Title, max 200';
COMMENT ON COLUMN profile.course.provider_name IS '[Public] Provider (NPTEL, Coursera), max 150';
COMMENT ON COLUMN profile.course.skill_id IS '[Public] Main skill taught; null: course spans several skills';
COMMENT ON COLUMN profile.course.course_url IS '[Public] Link to the course; null: offline course';
COMMENT ON COLUMN profile.course.duration_hours IS '[Public] Effort in hours; null: self-paced, not stated';
COMMENT ON COLUMN profile.course.is_active IS '[Public] Offered to candidates; default true';

CREATE TABLE profile.course_enrolment (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  course_id              bigint       NOT NULL,
  candidate_profile_id   bigint       NOT NULL,
  enrolment_status_code  d_code       NOT NULL DEFAULT 'enrolled',
  enrolled_on            date         NOT NULL,
  completed_on           date,
  certificate_url        varchar(500),
  created_at             timestamptz  NOT NULL DEFAULT now(),
  created_by             bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz  NOT NULL DEFAULT now(),
  updated_by             bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_course_enrolment PRIMARY KEY (id),
  CONSTRAINT fk_course_enrolment_course_id FOREIGN KEY (course_id) REFERENCES profile.course (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_course_enrolment_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_course_enrolment_enrolment_status_code FOREIGN KEY (enrolment_status_code) REFERENCES ref.enrolment_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.course_enrolment IS '[hard-delete] Candidate enrolment in a course (owned by the candidate)';
COMMENT ON COLUMN profile.course_enrolment.course_id IS '[Internal] Course';
COMMENT ON COLUMN profile.course_enrolment.candidate_profile_id IS '[Internal] Enrolled candidate';
COMMENT ON COLUMN profile.course_enrolment.enrolment_status_code IS '[Personal] enrolled, in_progress, completed, dropped; default enrolled';
COMMENT ON COLUMN profile.course_enrolment.enrolled_on IS '[Personal] Enrolment date';
COMMENT ON COLUMN profile.course_enrolment.completed_on IS '[Personal] Completion date; null: not completed';
COMMENT ON COLUMN profile.course_enrolment.certificate_url IS '[Personal] Completion certificate link; null: not completed or no certificate';

CREATE TABLE profile.profile_completion_score (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id  bigint         NOT NULL,
  completion_pct        d_pct          NOT NULL,
  missing_sections      varchar(40)[]  NOT NULL DEFAULT '{}',
  computed_at           timestamptz    NOT NULL DEFAULT now(),
  created_at            timestamptz    NOT NULL DEFAULT now(),
  created_by            bigint         NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz    NOT NULL DEFAULT now(),
  updated_by            bigint         NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_profile_completion_score PRIMARY KEY (id),
  CONSTRAINT fk_profile_completion_score_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE CASCADE
);
COMMENT ON TABLE  profile.profile_completion_score IS '[hard-delete] Current completion score of a profile (derived, one row per profile, recomputed on change)';
COMMENT ON COLUMN profile.profile_completion_score.candidate_profile_id IS '[Internal] Profile scored (unique in M6)';
COMMENT ON COLUMN profile.profile_completion_score.completion_pct IS '[Internal] Weighted completion 0-100';
COMMENT ON COLUMN profile.profile_completion_score.missing_sections IS '[Internal] Section codes still empty (contact, education ...); empty array when complete; default empty';
COMMENT ON COLUMN profile.profile_completion_score.computed_at IS '[Internal] When the score was last computed';

-- ---------------------------------------------------------------------------------------------------
-- Append-only history (RG10: actor, subject, timestamp). Leaf tables (no FK points at them): monthly range partitioning
-- can be added in M21 without rebuilding any FK (D5).
CREATE TABLE profile.profile_view_event (
  id                      bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id    bigint      NOT NULL,
  viewer_app_user_id      bigint      NOT NULL,
  viewer_organisation_id  bigint,
  viewed_at               timestamptz NOT NULL DEFAULT now(),
  created_at              timestamptz NOT NULL DEFAULT now(),
  created_by              bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_profile_view_event PRIMARY KEY (id),
  CONSTRAINT fk_profile_view_event_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_profile_view_event_viewer_app_user_id FOREIGN KEY (viewer_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_profile_view_event_viewer_organisation_id FOREIGN KEY (viewer_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.profile_view_event IS '[append-only] Which employer or recruiter viewed which profile, and when (profile view history). Paid views link their ledger debit in M14';
COMMENT ON COLUMN profile.profile_view_event.candidate_profile_id IS '[Internal] Profile viewed (subject)';
COMMENT ON COLUMN profile.profile_view_event.viewer_app_user_id IS '[Internal] User who viewed (actor)';
COMMENT ON COLUMN profile.profile_view_event.viewer_organisation_id IS '[Internal] Organisation the viewer acted for; null: independent consultant with no organisation';
COMMENT ON COLUMN profile.profile_view_event.viewed_at IS '[Internal] When the view happened (UTC); may precede created_at for batched events';

CREATE TABLE profile.candidate_activity_event (
  id                         bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id       bigint      NOT NULL,
  activity_event_type_code   d_code      NOT NULL,
  occurred_at                timestamptz NOT NULL DEFAULT now(),
  event_detail               jsonb,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  created_by                 bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_activity_event PRIMARY KEY (id),
  CONSTRAINT fk_candidate_activity_event_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_activity_event_activity_event_type_code FOREIGN KEY (activity_event_type_code) REFERENCES ref.activity_event_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_activity_event IS '[append-only] Candidate activity log: login, profile update, resume download ...';
COMMENT ON COLUMN profile.candidate_activity_event.candidate_profile_id IS '[Internal] Candidate (subject)';
COMMENT ON COLUMN profile.candidate_activity_event.activity_event_type_code IS '[Internal] Event type';
COMMENT ON COLUMN profile.candidate_activity_event.occurred_at IS '[Internal] When the event happened (UTC)';
COMMENT ON COLUMN profile.candidate_activity_event.event_detail IS '[Internal] Event-specific detail (section changed, resume id); null: event has no detail';

CREATE TABLE profile.candidate_bookmark_event (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id   bigint      NOT NULL,
  actor_app_user_id      bigint      NOT NULL,
  actor_organisation_id  bigint,
  job_requirement_id     bigint,
  bookmark_action_code   d_code      NOT NULL,
  occurred_at            timestamptz NOT NULL DEFAULT now(),
  created_at             timestamptz NOT NULL DEFAULT now(),
  created_by             bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_candidate_bookmark_event PRIMARY KEY (id),
  CONSTRAINT fk_candidate_bookmark_event_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_bookmark_event_actor_app_user_id FOREIGN KEY (actor_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_bookmark_event_actor_organisation_id FOREIGN KEY (actor_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_candidate_bookmark_event_bookmark_action_code FOREIGN KEY (bookmark_action_code) REFERENCES ref.bookmark_action (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.candidate_bookmark_event IS '[append-only] Bookmark added or removed by an employer or recruiter (bookmark history)';
COMMENT ON COLUMN profile.candidate_bookmark_event.candidate_profile_id IS '[Internal] Candidate bookmarked (subject)';
COMMENT ON COLUMN profile.candidate_bookmark_event.actor_app_user_id IS '[Internal] Recruiter or employer user (actor)';
COMMENT ON COLUMN profile.candidate_bookmark_event.actor_organisation_id IS '[Internal] Organisation the actor worked for; null: independent consultant';
COMMENT ON COLUMN profile.candidate_bookmark_event.job_requirement_id IS '[Internal] Job the bookmark is for; null: general talent-pool bookmark (FK added in 30_jobs.sql)';
COMMENT ON COLUMN profile.candidate_bookmark_event.bookmark_action_code IS '[Internal] added or removed';
COMMENT ON COLUMN profile.candidate_bookmark_event.occurred_at IS '[Internal] When it happened (UTC)';

CREATE TABLE profile.referral (
  id                             bigint GENERATED ALWAYS AS IDENTITY,
  referrer_app_user_id           bigint      NOT NULL,
  referred_candidate_profile_id  bigint,
  referred_email                 d_email,
  job_requirement_id             bigint,
  referral_status_code           d_code      NOT NULL DEFAULT 'invited',
  referred_at                    timestamptz NOT NULL DEFAULT now(),
  created_at                     timestamptz NOT NULL DEFAULT now(),
  created_by                     bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                     timestamptz NOT NULL DEFAULT now(),
  updated_by                     bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_referral PRIMARY KEY (id),
  CONSTRAINT fk_referral_referrer_app_user_id FOREIGN KEY (referrer_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_referral_referred_candidate_profile_id FOREIGN KEY (referred_candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_referral_referral_status_code FOREIGN KEY (referral_status_code) REFERENCES ref.referral_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  profile.referral IS '[hard-delete] Who referred whom, optionally for a job, and how far it progressed (referral tracking and events)';
COMMENT ON COLUMN profile.referral.referrer_app_user_id IS '[Internal] User who referred';
COMMENT ON COLUMN profile.referral.referred_candidate_profile_id IS '[Internal] Referred candidate; null: invitee has not registered yet, referred_email is set';
COMMENT ON COLUMN profile.referral.referred_email IS '[Personal] Invitee email; null: invitee already has a profile';
COMMENT ON COLUMN profile.referral.job_requirement_id IS '[Internal] Job referred for; null: platform referral, not for a specific job (FK added in 30_jobs.sql)';
COMMENT ON COLUMN profile.referral.referral_status_code IS '[Internal] invited, registered, applied, hired, expired; default invited';
COMMENT ON COLUMN profile.referral.referred_at IS '[Internal] When the referral was made (UTC)';

-- =====================================================================================================
-- M6: unique and check constraints, indexes (profile)
-- =====================================================================================================

ALTER TABLE profile.candidate_profile
  ADD CONSTRAINT uq_candidate_profile_app_user_id UNIQUE (app_user_id),
  ADD CONSTRAINT uq_candidate_profile_legacy_source_system_legacy_source_id UNIQUE (legacy_source_system, legacy_source_id),
  ADD CONSTRAINT ck_candidate_profile_legacy_source_pair CHECK ((legacy_source_system IS NULL) = (legacy_source_id IS NULL)),
  -- RG5: an amount exists exactly when it is disclosed; never 0 or '' for "unknown"
  ADD CONSTRAINT ck_candidate_profile_current_salary_disclosure
    CHECK ((current_salary_disclosure_code = 'disclosed') = (current_salary_amount IS NOT NULL)),
  ADD CONSTRAINT ck_candidate_profile_expected_salary_disclosure
    CHECK ((expected_salary_disclosure_code = 'disclosed') = (expected_salary_amount IS NOT NULL)),
  ADD CONSTRAINT ck_candidate_profile_salary_currency
    CHECK ((currency_code IS NULL) = (pay_period_code IS NULL)
           AND (currency_code IS NOT NULL) = (current_salary_amount IS NOT NULL OR expected_salary_amount IS NOT NULL)),
  ADD CONSTRAINT ck_candidate_profile_salary_non_negative CHECK (current_salary_amount >= 0 AND expected_salary_amount >= 0),
  ADD CONSTRAINT ck_candidate_profile_total_experience_months CHECK (total_experience_months BETWEEN 0 AND 840),
  ADD CONSTRAINT ck_candidate_profile_date_of_birth CHECK (date_of_birth > DATE '1900-01-01'),
  ADD CONSTRAINT ck_candidate_profile_headline_not_blank CHECK (btrim(headline) <> ''),
  ADD CONSTRAINT ck_candidate_profile_summary_not_blank CHECK (btrim(summary) <> ''),
  ADD CONSTRAINT ck_candidate_profile_summary_language CHECK (summary_language_id IS NULL OR summary IS NOT NULL);
CREATE INDEX idx_candidate_profile_current_city_id ON profile.candidate_profile (current_city_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_candidate_profile_full_name_trgm ON profile.candidate_profile USING gin (full_name gin_trgm_ops);

ALTER TABLE profile.candidate_contact
  ADD CONSTRAINT uq_candidate_contact_email UNIQUE (email),
  ADD CONSTRAINT ck_candidate_contact_value_by_type CHECK (
        (contact_type_code = 'email' AND email IS NOT NULL AND phone IS NULL AND phone_country_id IS NULL)
     OR (contact_type_code IN ('phone', 'whatsapp') AND phone IS NOT NULL AND phone_country_id IS NOT NULL AND email IS NULL)),
  ADD CONSTRAINT ck_candidate_contact_verified CHECK (is_verified = (verified_at IS NOT NULL));
CREATE UNIQUE INDEX uq_candidate_contact_primary_per_type ON profile.candidate_contact (candidate_profile_id, contact_type_code) WHERE is_primary;
CREATE INDEX idx_candidate_contact_candidate_profile_id ON profile.candidate_contact (candidate_profile_id);
CREATE INDEX idx_candidate_contact_phone ON profile.candidate_contact (phone) WHERE phone IS NOT NULL;

ALTER TABLE profile.candidate_address
  ADD CONSTRAINT ck_candidate_address_coordinates_pair CHECK ((latitude IS NULL) = (longitude IS NULL)),
  ADD CONSTRAINT ck_candidate_address_address_line1_not_blank CHECK (btrim(address_line1) <> '');
CREATE INDEX idx_candidate_address_candidate_profile_id ON profile.candidate_address (candidate_profile_id);

ALTER TABLE profile.candidate_identity_document
  ADD CONSTRAINT uq_candidate_identity_document_type_hash UNIQUE (identifier_type_code, identifier_hash),
  ADD CONSTRAINT uq_candidate_identity_document_profile_type UNIQUE (candidate_profile_id, identifier_type_code),
  ADD CONSTRAINT ck_candidate_identity_document_last4_format CHECK (identifier_last4 ~ '^[A-Z0-9]{4}$'),
  ADD CONSTRAINT ck_candidate_identity_document_hash_length CHECK (octet_length(identifier_hash) = 32),
  ADD CONSTRAINT ck_candidate_identity_document_verified CHECK (verification_status_code <> 'verified' OR verified_at IS NOT NULL);

ALTER TABLE profile.candidate_language
  ADD CONSTRAINT uq_candidate_language_candidate_profile_id_language_id UNIQUE (candidate_profile_id, language_id),
  ADD CONSTRAINT ck_candidate_language_some_ability CHECK (can_read OR can_write OR can_speak);

ALTER TABLE profile.candidate_education
  ADD CONSTRAINT ck_candidate_education_date_range CHECK (end_date IS NULL OR end_date >= start_date),
  ADD CONSTRAINT ck_candidate_education_institution CHECK ((institution_id IS NULL) <> (institution_name IS NULL)),
  ADD CONSTRAINT ck_candidate_education_single_score CHECK (score_pct IS NULL OR grade_text IS NULL),
  ADD CONSTRAINT ck_candidate_education_institution_name_not_blank CHECK (btrim(institution_name) <> '');
CREATE UNIQUE INDEX uq_candidate_education_one_highest ON profile.candidate_education (candidate_profile_id) WHERE is_highest;
CREATE INDEX idx_candidate_education_candidate_profile_id ON profile.candidate_education (candidate_profile_id);

ALTER TABLE profile.candidate_work_experience
  ADD CONSTRAINT ck_candidate_work_experience_date_range CHECK (end_date IS NULL OR end_date >= start_date),
  ADD CONSTRAINT ck_candidate_work_experience_employer CHECK ((organisation_id IS NULL) <> (employer_name IS NULL)),
  ADD CONSTRAINT ck_candidate_work_experience_current CHECK (is_current = (end_date IS NULL)),
  ADD CONSTRAINT ck_candidate_work_experience_description_language CHECK (description_language_id IS NULL OR description IS NOT NULL);
CREATE INDEX idx_candidate_work_experience_candidate_profile_id ON profile.candidate_work_experience (candidate_profile_id);
CREATE INDEX idx_candidate_work_experience_organisation_id ON profile.candidate_work_experience (organisation_id) WHERE organisation_id IS NOT NULL;

ALTER TABLE profile.candidate_skill
  ADD CONSTRAINT uq_candidate_skill_candidate_profile_id_skill_id UNIQUE (candidate_profile_id, skill_id),
  ADD CONSTRAINT ck_candidate_skill_experience_months CHECK (experience_months >= 0),
  ADD CONSTRAINT ck_candidate_skill_last_used_year CHECK (last_used_year BETWEEN 1950 AND 2100);
CREATE INDEX idx_candidate_skill_skill_id ON profile.candidate_skill (skill_id);

ALTER TABLE profile.candidate_certification
  ADD CONSTRAINT ck_candidate_certification_date_range CHECK (expiry_date IS NULL OR expiry_date >= issue_date);
CREATE INDEX idx_candidate_certification_candidate_profile_id ON profile.candidate_certification (candidate_profile_id);

ALTER TABLE profile.candidate_project
  ADD CONSTRAINT ck_candidate_project_date_range CHECK (end_date IS NULL OR end_date >= start_date),
  ADD CONSTRAINT ck_candidate_project_description_language CHECK (description_language_id IS NULL OR description IS NOT NULL);
CREATE INDEX idx_candidate_project_candidate_profile_id ON profile.candidate_project (candidate_profile_id);

ALTER TABLE profile.candidate_preferred_location
  ADD CONSTRAINT uq_candidate_preferred_location_candidate_profile_id_city_id UNIQUE (candidate_profile_id, city_id);
ALTER TABLE profile.candidate_preferred_role
  ADD CONSTRAINT uq_candidate_preferred_role_candidate_profile_id_job_role_id UNIQUE (candidate_profile_id, job_role_id);
ALTER TABLE profile.candidate_web_link
  ADD CONSTRAINT uq_candidate_web_link_candidate_profile_id_link_url UNIQUE (candidate_profile_id, link_url),
  ADD CONSTRAINT ck_candidate_web_link_link_url_format CHECK (link_url ~* '^https?://');

ALTER TABLE profile.resume_template ADD CONSTRAINT uq_resume_template_template_name UNIQUE (template_name);

ALTER TABLE profile.resume_version
  ADD CONSTRAINT uq_resume_version_candidate_profile_id_version_number UNIQUE (candidate_profile_id, version_number),
  ADD CONSTRAINT ck_resume_version_version_number CHECK (version_number > 0),
  ADD CONSTRAINT ck_resume_version_has_content CHECK (body IS NOT NULL OR file_storage_key IS NOT NULL),
  ADD CONSTRAINT ck_resume_version_file_metadata CHECK ((file_storage_key IS NULL) = (file_mime_type IS NULL)
                                                       AND (file_storage_key IS NULL) = (file_size_bytes IS NULL)),
  ADD CONSTRAINT ck_resume_version_file_size_bytes CHECK (file_size_bytes > 0),
  ADD CONSTRAINT ck_resume_version_body_language CHECK (body_language_id IS NULL OR body IS NOT NULL);
CREATE UNIQUE INDEX uq_resume_version_one_default ON profile.resume_version (candidate_profile_id) WHERE is_default AND deleted_at IS NULL;

ALTER TABLE profile.assessment
  ADD CONSTRAINT uq_assessment_assessment_name UNIQUE (assessment_name),
  ADD CONSTRAINT ck_assessment_max_score CHECK (max_score > 0),
  ADD CONSTRAINT ck_assessment_duration_minutes CHECK (duration_minutes > 0);

ALTER TABLE profile.assessment_attempt
  ADD CONSTRAINT ck_assessment_attempt_time_range CHECK (submitted_at >= started_at),
  ADD CONSTRAINT ck_assessment_attempt_raw_score CHECK (raw_score >= 0);
CREATE INDEX idx_assessment_attempt_candidate_profile_id ON profile.assessment_attempt (candidate_profile_id, submitted_at);

ALTER TABLE profile.course
  ADD CONSTRAINT uq_course_course_title_provider_name UNIQUE (course_title, provider_name),
  ADD CONSTRAINT ck_course_duration_hours CHECK (duration_hours > 0);

ALTER TABLE profile.course_enrolment
  ADD CONSTRAINT uq_course_enrolment_course_id_candidate_profile_id UNIQUE (course_id, candidate_profile_id),
  ADD CONSTRAINT ck_course_enrolment_date_range CHECK (completed_on IS NULL OR completed_on >= enrolled_on),
  ADD CONSTRAINT ck_course_enrolment_completed CHECK ((enrolment_status_code = 'completed') = (completed_on IS NOT NULL)),
  ADD CONSTRAINT ck_course_enrolment_certificate CHECK (certificate_url IS NULL OR completed_on IS NOT NULL);
CREATE INDEX idx_course_enrolment_candidate_profile_id ON profile.course_enrolment (candidate_profile_id);

ALTER TABLE profile.profile_completion_score
  ADD CONSTRAINT uq_profile_completion_score_candidate_profile_id UNIQUE (candidate_profile_id);

CREATE INDEX idx_profile_view_event_candidate_profile_id ON profile.profile_view_event (candidate_profile_id, viewed_at);
CREATE INDEX idx_profile_view_event_viewer_organisation_id ON profile.profile_view_event (viewer_organisation_id, viewed_at);
CREATE INDEX idx_candidate_activity_event_candidate_profile_id ON profile.candidate_activity_event (candidate_profile_id, occurred_at);
CREATE INDEX idx_candidate_bookmark_event_candidate_profile_id ON profile.candidate_bookmark_event (candidate_profile_id, occurred_at);
CREATE INDEX idx_candidate_bookmark_event_actor_app_user_id ON profile.candidate_bookmark_event (actor_app_user_id, occurred_at);

ALTER TABLE profile.referral
  ADD CONSTRAINT ck_referral_referred_party CHECK ((referred_candidate_profile_id IS NULL) <> (referred_email IS NULL));
CREATE INDEX idx_referral_referrer_app_user_id ON profile.referral (referrer_app_user_id);
