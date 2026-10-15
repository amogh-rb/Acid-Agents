-- Analytics layer and reporting marts (schema dw). Owner C. Phase 4: M15-M18 (B49, B52, B55, B58).
-- Entities and relationships: docs/phase4/dw_entities.md, dw_relationships.md.
-- Star schema for the hiring KPIs. Docket Section 8 (KPIs) was not issued; the marts serve the standard set:
-- funnel conversion by stage, time to hire, applications per job, volume by category (job and gig).
--   * dim_candidate and dim_job_requirement are SCD type 2: a changed attribute closes the current version
--     (valid_to, is_current = false) and opens a new one; facts join the version valid at applied_at
--   * dim_organisation is SCD type 1 (overwrite); dim_date is static
--   * fact_application holds one row per application from both pipelines (job.application and gig.gig_application),
--     keyed by (source_system, source_application_id): the "single view of the hiring pipeline" (docket Section 1)
--   * agg_daily_funnel is recomputed from the fact; dw.refresh_marts() is idempotent (running it twice changes nothing)
--     and records its run in etl_watermark
-- dw tables are [derived]: no audit columns (D6), read-only for the application, natural keys carry nofk (the warehouse
-- must survive operational purges).

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
CREATE TABLE dw.dim_date (
  id             bigint GENERATED ALWAYS AS IDENTITY,
  calendar_date  date     NOT NULL,
  year_number    smallint NOT NULL,
  quarter_number smallint NOT NULL,
  month_number   smallint NOT NULL,
  iso_week       smallint NOT NULL,
  day_of_week    smallint NOT NULL,
  is_weekend     boolean  NOT NULL DEFAULT false,
  CONSTRAINT pk_dim_date PRIMARY KEY (id),
  CONSTRAINT uq_dim_date_calendar_date UNIQUE (calendar_date)
);
COMMENT ON TABLE  dw.dim_date IS '[derived] Calendar dimension, one row per day 2024-2028';
COMMENT ON COLUMN dw.dim_date.calendar_date IS '[Public] The day';
COMMENT ON COLUMN dw.dim_date.year_number IS '[Public] Calendar year';
COMMENT ON COLUMN dw.dim_date.quarter_number IS '[Public] Quarter 1-4';
COMMENT ON COLUMN dw.dim_date.month_number IS '[Public] Month 1-12';
COMMENT ON COLUMN dw.dim_date.iso_week IS '[Public] ISO week number';
COMMENT ON COLUMN dw.dim_date.day_of_week IS '[Public] ISO day of week, 1 = Monday';
COMMENT ON COLUMN dw.dim_date.is_weekend IS '[Public] Saturday or Sunday; default false';
INSERT INTO dw.dim_date (calendar_date, year_number, quarter_number, month_number, iso_week, day_of_week, is_weekend)
SELECT d::date, extract(year FROM d), extract(quarter FROM d), extract(month FROM d), extract(week FROM d),
       extract(isodow FROM d), extract(isodow FROM d) IN (6, 7)
  FROM generate_series(DATE '2024-01-01', DATE '2028-12-31', interval '1 day') d;

CREATE TABLE dw.dim_organisation (
  id                 bigint GENERATED ALWAYS AS IDENTITY,
  organisation_id    bigint       NOT NULL,
  organisation_name  varchar(200) NOT NULL,
  organisation_type  varchar(40)  NOT NULL,
  industry_name      varchar(150),
  row_hash           bytea        NOT NULL,
  loaded_at          timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT pk_dim_organisation PRIMARY KEY (id),
  CONSTRAINT uq_dim_organisation_organisation_id UNIQUE (organisation_id)
);
COMMENT ON TABLE  dw.dim_organisation IS '[derived] Organisation dimension, SCD type 1 (attributes overwritten in place)';
COMMENT ON COLUMN dw.dim_organisation.organisation_id IS '[Internal] Natural key: org.organisation.id; nofk: warehouse keeps history after operational purges';
COMMENT ON COLUMN dw.dim_organisation.organisation_name IS '[Public] Display name';
COMMENT ON COLUMN dw.dim_organisation.organisation_type IS '[Public] employer, client, staffing_agency ... (code copied, not a FK)';
COMMENT ON COLUMN dw.dim_organisation.industry_name IS '[Public] Industry; null: not provided by the organisation';
COMMENT ON COLUMN dw.dim_organisation.row_hash IS '[Internal] SHA-256 of the tracked attributes; change detection';
COMMENT ON COLUMN dw.dim_organisation.loaded_at IS '[Internal] Last load (UTC)';

CREATE TABLE dw.dim_candidate (
  id                           bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id         bigint       NOT NULL,
  city_name                    varchar(100),
  experience_band              varchar(20)  NOT NULL,
  highest_qualification_level  varchar(40),
  row_hash                     bytea        NOT NULL,
  valid_from                   timestamptz  NOT NULL,
  valid_to                     timestamptz,
  is_current                   boolean      NOT NULL DEFAULT true,
  CONSTRAINT pk_dim_candidate PRIMARY KEY (id),
  CONSTRAINT ck_dim_candidate_validity CHECK (valid_to IS NULL OR valid_to > valid_from),
  CONSTRAINT ck_dim_candidate_current CHECK (is_current = (valid_to IS NULL))
);
CREATE UNIQUE INDEX uq_dim_candidate_current ON dw.dim_candidate (candidate_profile_id) WHERE is_current;
CREATE INDEX idx_dim_candidate_candidate_profile_id ON dw.dim_candidate (candidate_profile_id, valid_from);
COMMENT ON TABLE  dw.dim_candidate IS '[derived] Candidate dimension, SCD type 2: one version per change of city, experience band or highest qualification. No direct identifiers (name, contact) are copied to the warehouse';
COMMENT ON COLUMN dw.dim_candidate.candidate_profile_id IS '[Internal] Natural key: profile.candidate_profile.id; nofk: warehouse keeps history after operational purges';
COMMENT ON COLUMN dw.dim_candidate.city_name IS '[Internal] Current city at this version; null: not provided';
COMMENT ON COLUMN dw.dim_candidate.experience_band IS '[Internal] fresher, 0-2y, 2-5y, 5-10y, 10y+, unknown';
COMMENT ON COLUMN dw.dim_candidate.highest_qualification_level IS '[Internal] Level of the highest qualification; null: no education entered';
COMMENT ON COLUMN dw.dim_candidate.row_hash IS '[Internal] SHA-256 of the tracked attributes; a different hash opens a new version';
COMMENT ON COLUMN dw.dim_candidate.valid_from IS '[Internal] Version start (UTC); the first version starts at the profile creation time';
COMMENT ON COLUMN dw.dim_candidate.valid_to IS '[Internal] Version end (UTC); null: current version';
COMMENT ON COLUMN dw.dim_candidate.is_current IS '[Internal] Current version (exactly one per candidate); default true';

CREATE TABLE dw.dim_job_requirement (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  job_requirement_id  bigint       NOT NULL,
  dim_organisation_id bigint       NOT NULL,
  job_category        varchar(40)  NOT NULL,
  job_role_name       varchar(150) NOT NULL,
  salary_band         varchar(20)  NOT NULL,
  row_hash            bytea        NOT NULL,
  valid_from          timestamptz  NOT NULL,
  valid_to            timestamptz,
  is_current          boolean      NOT NULL DEFAULT true,
  CONSTRAINT pk_dim_job_requirement PRIMARY KEY (id),
  CONSTRAINT fk_dim_job_requirement_dim_organisation_id FOREIGN KEY (dim_organisation_id) REFERENCES dw.dim_organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_dim_job_requirement_validity CHECK (valid_to IS NULL OR valid_to > valid_from),
  CONSTRAINT ck_dim_job_requirement_current CHECK (is_current = (valid_to IS NULL))
);
CREATE UNIQUE INDEX uq_dim_job_requirement_current ON dw.dim_job_requirement (job_requirement_id) WHERE is_current;
CREATE INDEX idx_dim_job_requirement_job_requirement_id ON dw.dim_job_requirement (job_requirement_id, valid_from);
CREATE INDEX idx_dim_job_requirement_dim_organisation_id ON dw.dim_job_requirement (dim_organisation_id);
COMMENT ON TABLE  dw.dim_job_requirement IS '[derived] Job requirement dimension, SCD type 2 on category, role, salary band and owner';
COMMENT ON COLUMN dw.dim_job_requirement.job_requirement_id IS '[Internal] Natural key: job.job_requirement.id; nofk: warehouse keeps history after operational purges';
COMMENT ON COLUMN dw.dim_job_requirement.dim_organisation_id IS '[Internal] Owning organisation';
COMMENT ON COLUMN dw.dim_job_requirement.job_category IS '[Public] Job category code (copied)';
COMMENT ON COLUMN dw.dim_job_requirement.job_role_name IS '[Public] Standard role';
COMMENT ON COLUMN dw.dim_job_requirement.salary_band IS '[Public] Annualised band: undisclosed, <3L, 3-6L, 6-12L, 12-25L, 25L+';
COMMENT ON COLUMN dw.dim_job_requirement.row_hash IS '[Internal] SHA-256 of the tracked attributes';
COMMENT ON COLUMN dw.dim_job_requirement.valid_from IS '[Internal] Version start (UTC); the first version starts at the job creation time';
COMMENT ON COLUMN dw.dim_job_requirement.valid_to IS '[Internal] Version end (UTC); null: current version';
COMMENT ON COLUMN dw.dim_job_requirement.is_current IS '[Internal] Current version; default true';

CREATE TABLE dw.fact_application (
  id                      bigint GENERATED ALWAYS AS IDENTITY,
  source_system           varchar(10)  NOT NULL,
  source_application_id   bigint       NOT NULL,
  dim_candidate_id        bigint,
  dim_job_requirement_id  bigint,
  dim_organisation_id     bigint,
  applied_dim_date_id     bigint       NOT NULL,
  job_category            varchar(40)  NOT NULL,
  current_status          varchar(40)  NOT NULL,
  reached_shortlisted     boolean      NOT NULL DEFAULT false,
  reached_interviewed     boolean      NOT NULL DEFAULT false,
  reached_offered         boolean      NOT NULL DEFAULT false,
  is_joined               boolean      NOT NULL DEFAULT false,
  days_to_hire            integer,
  loaded_at               timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT pk_fact_application PRIMARY KEY (id),
  CONSTRAINT uq_fact_application_source UNIQUE (source_system, source_application_id),
  CONSTRAINT fk_fact_application_dim_candidate_id FOREIGN KEY (dim_candidate_id) REFERENCES dw.dim_candidate (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_fact_application_dim_job_requirement_id FOREIGN KEY (dim_job_requirement_id) REFERENCES dw.dim_job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_fact_application_dim_organisation_id FOREIGN KEY (dim_organisation_id) REFERENCES dw.dim_organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_fact_application_applied_dim_date_id FOREIGN KEY (applied_dim_date_id) REFERENCES dw.dim_date (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_fact_application_source_system CHECK (source_system IN ('job', 'gig')),
  CONSTRAINT ck_fact_application_job_dims CHECK (source_system = 'gig' OR (dim_candidate_id IS NOT NULL AND dim_job_requirement_id IS NOT NULL)),
  CONSTRAINT ck_fact_application_days_to_hire CHECK (days_to_hire IS NULL OR (days_to_hire >= 0 AND is_joined))
);
CREATE INDEX idx_fact_application_applied_dim_date_id ON dw.fact_application (applied_dim_date_id, job_category);
CREATE INDEX idx_fact_application_dim_job_requirement_id ON dw.fact_application (dim_job_requirement_id);
CREATE INDEX idx_fact_application_dim_candidate_id ON dw.fact_application (dim_candidate_id);
CREATE INDEX idx_fact_application_dim_organisation_id ON dw.fact_application (dim_organisation_id);
COMMENT ON TABLE  dw.fact_application IS '[derived] One row per application from the job pipeline and the gig subsystem (single pipeline view); grain = application';
COMMENT ON COLUMN dw.fact_application.source_system IS '[Internal] job or gig';
COMMENT ON COLUMN dw.fact_application.source_application_id IS '[Internal] job.application.id or gig.gig_application.id; nofk: two possible sources, unique with source_system';
COMMENT ON COLUMN dw.fact_application.dim_candidate_id IS '[Internal] Candidate version valid when applying; null: gig application (gig workers are not candidates)';
COMMENT ON COLUMN dw.fact_application.dim_job_requirement_id IS '[Internal] Job version valid when applying; null: gig application';
COMMENT ON COLUMN dw.fact_application.dim_organisation_id IS '[Internal] Hiring organisation; null: gig posted by an individual requester';
COMMENT ON COLUMN dw.fact_application.applied_dim_date_id IS '[Internal] Application date';
COMMENT ON COLUMN dw.fact_application.job_category IS '[Internal] Job category, or gig';
COMMENT ON COLUMN dw.fact_application.current_status IS '[Internal] Latest status code (copied)';
COMMENT ON COLUMN dw.fact_application.reached_shortlisted IS '[Internal] Ever shortlisted (gig: accepted); default false';
COMMENT ON COLUMN dw.fact_application.reached_interviewed IS '[Internal] Ever interviewed; default false';
COMMENT ON COLUMN dw.fact_application.reached_offered IS '[Internal] Ever offered (gig: accepted); default false';
COMMENT ON COLUMN dw.fact_application.is_joined IS '[Internal] Joined (gig: assignment completed); default false';
COMMENT ON COLUMN dw.fact_application.days_to_hire IS '[Internal] Days from application to joining; null: not joined';
COMMENT ON COLUMN dw.fact_application.loaded_at IS '[Internal] Last load of this row (UTC)';

CREATE TABLE dw.agg_daily_funnel (
  id                 bigint GENERATED ALWAYS AS IDENTITY,
  dim_date_id        bigint      NOT NULL,
  job_category       varchar(40) NOT NULL,
  applied_count      integer     NOT NULL,
  shortlisted_count  integer     NOT NULL,
  interviewed_count  integer     NOT NULL,
  offered_count      integer     NOT NULL,
  joined_count       integer     NOT NULL,
  avg_days_to_hire   numeric(8,2),
  refreshed_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_agg_daily_funnel PRIMARY KEY (id),
  CONSTRAINT uq_agg_daily_funnel_date_category UNIQUE (dim_date_id, job_category),
  CONSTRAINT fk_agg_daily_funnel_dim_date_id FOREIGN KEY (dim_date_id) REFERENCES dw.dim_date (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_agg_daily_funnel_funnel CHECK (applied_count >= shortlisted_count AND shortlisted_count >= 0
                                               AND joined_count <= applied_count AND interviewed_count >= 0 AND offered_count >= 0)
);
COMMENT ON TABLE  dw.agg_daily_funnel IS '[derived] Daily hiring funnel per job category (applied, shortlisted, interviewed, offered, joined, time to hire), recomputed from fact_application';
COMMENT ON COLUMN dw.agg_daily_funnel.dim_date_id IS '[Internal] Application date';
COMMENT ON COLUMN dw.agg_daily_funnel.job_category IS '[Internal] Job category, or gig';
COMMENT ON COLUMN dw.agg_daily_funnel.applied_count IS '[Internal] Applications made that day';
COMMENT ON COLUMN dw.agg_daily_funnel.shortlisted_count IS '[Internal] Of those, ever shortlisted';
COMMENT ON COLUMN dw.agg_daily_funnel.interviewed_count IS '[Internal] Of those, ever interviewed';
COMMENT ON COLUMN dw.agg_daily_funnel.offered_count IS '[Internal] Of those, ever offered';
COMMENT ON COLUMN dw.agg_daily_funnel.joined_count IS '[Internal] Of those, joined';
COMMENT ON COLUMN dw.agg_daily_funnel.avg_days_to_hire IS '[Internal] Mean days to hire of the joined ones; null: nobody joined';
COMMENT ON COLUMN dw.agg_daily_funnel.refreshed_at IS '[Internal] Last recomputation (UTC)';

CREATE TABLE dw.etl_watermark (
  id                  bigint GENERATED ALWAYS AS IDENTITY,
  process_name        varchar(60) NOT NULL,
  last_run_started_at timestamptz,
  last_run_ended_at   timestamptz,
  rows_changed        bigint      NOT NULL DEFAULT 0,
  CONSTRAINT pk_etl_watermark PRIMARY KEY (id),
  CONSTRAINT uq_etl_watermark_process_name UNIQUE (process_name),
  CONSTRAINT ck_etl_watermark_time_range CHECK (last_run_ended_at IS NULL OR last_run_ended_at >= last_run_started_at)
);
COMMENT ON TABLE  dw.etl_watermark IS '[derived] Bookkeeping of each refresh process: when it last ran and how much changed';
COMMENT ON COLUMN dw.etl_watermark.process_name IS '[Internal] Refresh process name';
COMMENT ON COLUMN dw.etl_watermark.last_run_started_at IS '[Internal] Last run start (UTC); null: never run';
COMMENT ON COLUMN dw.etl_watermark.last_run_ended_at IS '[Internal] Last run end (UTC); null: never run or running';
COMMENT ON COLUMN dw.etl_watermark.rows_changed IS '[Internal] Rows inserted or changed by the last run; default 0';

-- ---------------------------------------------------------------------------------------------------
-- Refresh: idempotent (hash-compared SCD2, upserted facts, recomputed aggregate). Reads operational tables as owner
-- (RLS does not apply to the warehouse load). At full scale the source scans become incremental on updated_at (M21).
CREATE FUNCTION dw.refresh_marts() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_started  timestamptz := clock_timestamp();
  v_now      timestamptz := clock_timestamp();   -- version boundaries must advance even within one transaction
  v_n        bigint;
  v_changed  bigint := 0;
  v_result   jsonb := '{}';
BEGIN
  -- dim_organisation (SCD1)
  INSERT INTO dw.dim_organisation (organisation_id, organisation_name, organisation_type, industry_name, row_hash)
  SELECT o.id, o.organisation_name, o.organisation_type_code, i.industry_name,
         digest(concat_ws('|', o.organisation_name, o.organisation_type_code, i.industry_name), 'sha256')
    FROM org.organisation o LEFT JOIN ref.industry i ON i.id = o.industry_id
  ON CONFLICT (organisation_id) DO UPDATE
     SET organisation_name = EXCLUDED.organisation_name, organisation_type = EXCLUDED.organisation_type,
         industry_name = EXCLUDED.industry_name, row_hash = EXCLUDED.row_hash, loaded_at = now()
   WHERE dw.dim_organisation.row_hash IS DISTINCT FROM EXCLUDED.row_hash;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed + v_n; v_result := v_result || jsonb_build_object('dim_organisation', v_n);

  -- dim_candidate (SCD2)
  DROP TABLE IF EXISTS tmp_candidate;
  CREATE TEMP TABLE tmp_candidate ON COMMIT DROP AS
  SELECT cp.id AS candidate_profile_id, cp.created_at, c.city_name,
         CASE WHEN cp.total_experience_months IS NULL THEN 'unknown'
              WHEN cp.total_experience_months = 0 THEN 'fresher'
              WHEN cp.total_experience_months < 24 THEN '0-2y'
              WHEN cp.total_experience_months < 60 THEN '2-5y'
              WHEN cp.total_experience_months < 120 THEN '5-10y' ELSE '10y+' END AS experience_band,
         (SELECT q.qualification_level_code FROM profile.candidate_education e
            JOIN ref.qualification q ON q.id = e.qualification_id
            JOIN ref.qualification_level ql ON ql.code = q.qualification_level_code
           WHERE e.candidate_profile_id = cp.id ORDER BY ql.level_rank DESC LIMIT 1) AS highest_qualification_level
    FROM profile.candidate_profile cp LEFT JOIN ref.city c ON c.id = cp.current_city_id
   WHERE cp.deleted_at IS NULL;
  ALTER TABLE tmp_candidate ADD COLUMN row_hash bytea;
  UPDATE tmp_candidate SET row_hash = digest(concat_ws('|', city_name, experience_band, highest_qualification_level), 'sha256');

  UPDATE dw.dim_candidate d SET valid_to = v_now, is_current = false
    FROM tmp_candidate s
   WHERE d.candidate_profile_id = s.candidate_profile_id AND d.is_current AND d.row_hash <> s.row_hash;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed + v_n;
  INSERT INTO dw.dim_candidate (candidate_profile_id, city_name, experience_band, highest_qualification_level, row_hash, valid_from)
  SELECT s.candidate_profile_id, s.city_name, s.experience_band, s.highest_qualification_level, s.row_hash,
         coalesce((SELECT max(valid_to) FROM dw.dim_candidate p WHERE p.candidate_profile_id = s.candidate_profile_id), s.created_at)
    FROM tmp_candidate s
   WHERE NOT EXISTS (SELECT 1 FROM dw.dim_candidate d WHERE d.candidate_profile_id = s.candidate_profile_id AND d.is_current);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed + v_n; v_result := v_result || jsonb_build_object('dim_candidate_new_versions', v_n);

  -- dim_job_requirement (SCD2)
  DROP TABLE IF EXISTS tmp_job;
  CREATE TEMP TABLE tmp_job ON COMMIT DROP AS
  SELECT j.id AS job_requirement_id, j.created_at, dorg.id AS dim_organisation_id, j.job_category_code AS job_category,
         r.role_name AS job_role_name,
         CASE WHEN j.salary_disclosure_code <> 'disclosed' THEN 'undisclosed'
              WHEN coalesce(j.salary_max, j.salary_min) * pp.annual_multiplier < 300000 THEN '<3L'
              WHEN coalesce(j.salary_max, j.salary_min) * pp.annual_multiplier < 600000 THEN '3-6L'
              WHEN coalesce(j.salary_max, j.salary_min) * pp.annual_multiplier < 1200000 THEN '6-12L'
              WHEN coalesce(j.salary_max, j.salary_min) * pp.annual_multiplier < 2500000 THEN '12-25L' ELSE '25L+' END AS salary_band
    FROM job.job_requirement j
    JOIN dw.dim_organisation dorg ON dorg.organisation_id = j.organisation_id
    JOIN ref.job_role r ON r.id = j.job_role_id
    LEFT JOIN ref.pay_period pp ON pp.code = j.pay_period_code;
  ALTER TABLE tmp_job ADD COLUMN row_hash bytea;
  UPDATE tmp_job SET row_hash = digest(concat_ws('|', dim_organisation_id, job_category, job_role_name, salary_band), 'sha256');
  UPDATE dw.dim_job_requirement d SET valid_to = v_now, is_current = false
    FROM tmp_job s
   WHERE d.job_requirement_id = s.job_requirement_id AND d.is_current AND d.row_hash <> s.row_hash;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed + v_n;
  INSERT INTO dw.dim_job_requirement (job_requirement_id, dim_organisation_id, job_category, job_role_name, salary_band, row_hash, valid_from)
  SELECT s.job_requirement_id, s.dim_organisation_id, s.job_category, s.job_role_name, s.salary_band, s.row_hash,
         coalesce((SELECT max(valid_to) FROM dw.dim_job_requirement p WHERE p.job_requirement_id = s.job_requirement_id), s.created_at)
    FROM tmp_job s
   WHERE NOT EXISTS (SELECT 1 FROM dw.dim_job_requirement d WHERE d.job_requirement_id = s.job_requirement_id AND d.is_current);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed + v_n; v_result := v_result || jsonb_build_object('dim_job_requirement_new_versions', v_n);

  -- fact_application: job pipeline (dimension versions valid at applied_at)
  INSERT INTO dw.fact_application AS f (source_system, source_application_id, dim_candidate_id, dim_job_requirement_id,
                                        dim_organisation_id, applied_dim_date_id, job_category, current_status,
                                        reached_shortlisted, reached_interviewed, reached_offered, is_joined, days_to_hire)
  SELECT 'job', a.id, dc.id, dj.id, dj.dim_organisation_id, dd.id, dj.job_category, a.application_status_code,
         EXISTS (SELECT 1 FROM job.application_status_history h WHERE h.application_id = a.id AND h.to_application_status_code = 'shortlisted'),
         EXISTS (SELECT 1 FROM job.application_status_history h WHERE h.application_id = a.id AND h.to_application_status_code = 'interviewed'),
         EXISTS (SELECT 1 FROM job.application_status_history h WHERE h.application_id = a.id AND h.to_application_status_code = 'offered'),
         a.application_status_code = 'joined',
         CASE WHEN a.application_status_code = 'joined' THEN (a.status_changed_at::date - a.applied_at::date) END
    FROM job.application a
    JOIN dw.dim_candidate dc ON dc.candidate_profile_id = a.candidate_profile_id
                            AND a.applied_at >= dc.valid_from AND (dc.valid_to IS NULL OR a.applied_at < dc.valid_to)
    JOIN dw.dim_job_requirement dj ON dj.job_requirement_id = a.job_requirement_id
                                  AND a.applied_at >= dj.valid_from AND (dj.valid_to IS NULL OR a.applied_at < dj.valid_to)
    JOIN dw.dim_date dd ON dd.calendar_date = a.applied_at::date
  ON CONFLICT (source_system, source_application_id) DO UPDATE
     SET current_status = EXCLUDED.current_status, reached_shortlisted = EXCLUDED.reached_shortlisted,
         reached_interviewed = EXCLUDED.reached_interviewed, reached_offered = EXCLUDED.reached_offered,
         is_joined = EXCLUDED.is_joined, days_to_hire = EXCLUDED.days_to_hire, loaded_at = now()
   WHERE (f.current_status, f.reached_shortlisted, f.reached_interviewed, f.reached_offered, f.is_joined, f.days_to_hire)
         IS DISTINCT FROM (EXCLUDED.current_status, EXCLUDED.reached_shortlisted, EXCLUDED.reached_interviewed,
                           EXCLUDED.reached_offered, EXCLUDED.is_joined, EXCLUDED.days_to_hire);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed + v_n; v_result := v_result || jsonb_build_object('fact_job_rows', v_n);

  -- fact_application: gig subsystem
  INSERT INTO dw.fact_application AS f (source_system, source_application_id, dim_organisation_id, applied_dim_date_id,
                                        job_category, current_status, reached_shortlisted, reached_offered, is_joined, days_to_hire)
  SELECT 'gig', ga.id, dorg.id, dd.id, 'gig', ga.gig_application_status_code,
         ga.gig_application_status_code = 'accepted', ga.gig_application_status_code = 'accepted',
         coalesce(asg.gig_assignment_status_code = 'completed', false),
         CASE WHEN asg.gig_assignment_status_code = 'completed' THEN (asg.completed_at::date - ga.applied_at::date) END
    FROM gig.gig_application ga
    JOIN gig.gig_request r ON r.id = ga.gig_request_id
    LEFT JOIN dw.dim_organisation dorg ON dorg.organisation_id = r.requester_organisation_id
    LEFT JOIN gig.gig_assignment asg ON asg.gig_application_id = ga.id
    JOIN dw.dim_date dd ON dd.calendar_date = ga.applied_at::date
  ON CONFLICT (source_system, source_application_id) DO UPDATE
     SET current_status = EXCLUDED.current_status, reached_shortlisted = EXCLUDED.reached_shortlisted,
         reached_offered = EXCLUDED.reached_offered, is_joined = EXCLUDED.is_joined, days_to_hire = EXCLUDED.days_to_hire,
         loaded_at = now()
   WHERE (f.current_status, f.reached_shortlisted, f.reached_offered, f.is_joined, f.days_to_hire)
         IS DISTINCT FROM (EXCLUDED.current_status, EXCLUDED.reached_shortlisted, EXCLUDED.reached_offered,
                           EXCLUDED.is_joined, EXCLUDED.days_to_hire);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed + v_n; v_result := v_result || jsonb_build_object('fact_gig_rows', v_n);

  -- agg_daily_funnel: recomputed from the fact (idempotent)
  DELETE FROM dw.agg_daily_funnel;
  INSERT INTO dw.agg_daily_funnel (dim_date_id, job_category, applied_count, shortlisted_count, interviewed_count,
                                   offered_count, joined_count, avg_days_to_hire)
  SELECT applied_dim_date_id, job_category, count(*), count(*) FILTER (WHERE reached_shortlisted),
         count(*) FILTER (WHERE reached_interviewed), count(*) FILTER (WHERE reached_offered),
         count(*) FILTER (WHERE is_joined), round(avg(days_to_hire), 2)
    FROM dw.fact_application
   GROUP BY applied_dim_date_id, job_category;

  INSERT INTO dw.etl_watermark (process_name, last_run_started_at, last_run_ended_at, rows_changed)
  VALUES ('refresh_marts', v_started, clock_timestamp(), v_changed)
  ON CONFLICT (process_name) DO UPDATE
     SET last_run_started_at = EXCLUDED.last_run_started_at, last_run_ended_at = EXCLUDED.last_run_ended_at,
         rows_changed = EXCLUDED.rows_changed;
  RETURN v_result || jsonb_build_object('rows_changed', v_changed);
END
$$;
REVOKE ALL ON FUNCTION dw.refresh_marts() FROM PUBLIC;

-- Default reporting surface
CREATE VIEW dw.v_funnel_by_category AS
SELECT d.year_number, d.month_number, f.job_category,
       sum(f.applied_count) AS applied, sum(f.shortlisted_count) AS shortlisted, sum(f.interviewed_count) AS interviewed,
       sum(f.offered_count) AS offered, sum(f.joined_count) AS joined,
       round(100.0 * sum(f.joined_count) / nullif(sum(f.applied_count), 0), 2) AS join_rate_pct
  FROM dw.agg_daily_funnel f JOIN dw.dim_date d ON d.id = f.dim_date_id
 GROUP BY d.year_number, d.month_number, f.job_category;
COMMENT ON VIEW dw.v_funnel_by_category IS 'Monthly hiring funnel and join rate per job category (KPI view)';
GRANT SELECT ON dw.v_funnel_by_category TO talentra_app, talentra_readonly;
