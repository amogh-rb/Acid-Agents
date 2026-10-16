# Talentra DB design: ACID Agents (project context)

This file is the hand-off between chats. Each milestone is built in a fresh chat, so **read this, then `docs/milestones.md`**, before doing anything. Update the "Current state" and "Handoff log" sections at the end of every milestone.

## What this is
- A hackathon (Northbridge "Talentra"): design, build and defend the PostgreSQL database for a job search and demand management platform.
- Team A, B, C. Core gate: M1-M14 built, verified and tested.

**Sources of truth**
- **Docket (requirements, rule groups 1-10):** `C:\Users\Administrator\Downloads\Talentra-Database-Design-Hackathon-Docket.pdf`. It is confidential and not in the repo.
- **`docs/reference/Talentra_Milestone_Plan.md`:** the order of work, the definition of done, and the per-milestone tests. Follow it.
- **`docs/reference/Talentra_Delivery_Plan.pdf`:** design decisions and the entity lists (section 4 = the "merged plan section 5" that the milestone plan cites).
- **`docs/00_decisions.md`:** frozen conventions and the deviations log. `docs/01_module_list.md`: owners and the domain-to-module mapping.

## Environment
- Windows 11, PowerShell 5.1, PostgreSQL 18.4 (local service), Python 3.11.
- `.env` (git-ignored) holds PGHOST, PGUSER, PGPASSWORD, PGBIN and TALENTRA_DB. psql is at `C:\Program Files\PostgreSQL\18\bin`.
- C: has about 19 GB free; D: has ~150 GB after the seed. Seed data is in tablespace `talentra_data` (`D:\talentra_pg`); WAL is on `D:\talentra_pg_wal`.
- Git:
  - Remote: `origin` = github.com/amogh-rb/Acid-Agents (private). gh account: rsiddarth10 (write access).
  - `Desktop/` is an unrelated git repo. Never commit there.
  - Commit on `main` for team milestones. Members' modules (M7-M14) go on their own branches.

## Commands
```
.\run.ps1 up                 # drop/recreate talentra, apply ddl/*.sql in name order
.\run.ps1 gate M6            # up + harness + every tests/**/mNN_*.sql|ps1 with NN <= 6
.\run.ps1 test [-Evidence]   # gate for the highest milestone with tests; run before every commit
.\run.ps1 lint               # lint the current DB
.\run.ps1 dict               # dictionary/columns.csv, tables.csv (commit them; m05 checks they are fresh)
.\run.ps1 erd -Schemas ref,profile,job -Out docs/erd/phase1_generated.mmd
python tools/reserved_words.py docs/phase1/entities.md
python tools/design_docs.py relations docs/phase1/entities.md docs/phase1/relationships.md
python tools/design_docs.py erd docs/phase1/entities.md docs/phase1/relationships.md docs/erd/phase1.mmd   # regenerate after editing relationships
python tools/design_docs.py compare docs/phase1/entities.md docs/phase1/relationships.md dictionary/columns.csv dictionary/tables.csv
```

## Layout
- `ddl/NN_*.sql`: applied in order.
  - Already present: `00` extensions/schemas/roles, `05` domains, `06` base functions, `07` ui_label/language/ui_translation, `99_finalise` (always last).
  - Built: `10_ref`, `15_stubs`, `20_profile`, `30_jobs`, `40_admin`, `45_org`, `50_gig`, `60_lic`, `65_src`, `70_billing`, `80_notif`, `85_access`, `90_dw`, `99_finalise`.
- `seed/NN_*.sql`: the M19 generator (server-side SQL); `seed/_preamble.sql` is included by each file. `.\run.ps1 seed -Scale rehearsal|laptop` builds `talentra_seed`.
- `tests/_qa/`: the harness (`qa.expect_error`, `qa.expect_ok`, `qa.assert`, `qa.assert_equals`, `qa.lint_violations()`).
- `tests/<area>/mNN_*.sql`: each file runs inside BEGIN ... ROLLBACK. `mNN_*.ps1` is for concurrency tests.
- `tools/`: dictionary/ERD export, reserved-word lists and checker, `pg_settings.sql`.
- `docs/`: decisions, module list, environment, the milestones board, `phase1/`, `erd/`, `evidence/`.

## Rules every new table must follow (the lint enforces them; `99_finalise` applies the rest)
1. **Schema and name:** schema per module; singular snake_case name; no PG/MySQL reserved words.
2. **Primary key:** `id bigint GENERATED ALWAYS AS IDENTITY`, `CONSTRAINT pk_<table> PRIMARY KEY (id)`.
3. **Audit columns:** write them out with defaults (seed rows are inserted before `99_finalise` runs):
   ```
   created_at timestamptz NOT NULL DEFAULT now(),
   created_by bigint NOT NULL DEFAULT public.current_actor_id(),
   updated_at timestamptz NOT NULL DEFAULT now(),
   updated_by bigint NOT NULL DEFAULT public.current_actor_id(),
   ```
   Append-only tables have `created_*` only. Soft-delete tables add `deleted_at timestamptz`.
4. **Constraint names:** `fk_<table>_<col>`, `uq_<table>_<cols>`, `ck_<table>_<rule>`, `ex_<table>_<rule>`, `idx_<table>_<cols>`, `trg_<table>_<purpose>`. Every FK states `ON UPDATE ... ON DELETE ...`: RESTRICT by default, CASCADE only for owned children.
5. **References:** every `*_id` / `*_code` column has an FK, or the comment says `nofk: <reason>`. Lookups are referenced by `code` (d_code).
6. **Domains:** d_person_name, d_email, d_phone_e164 (plus `<col>_country_id`), d_money (plus `<col>_currency_code` or `currency_code`), d_pct, d_lat/d_lng, d_code, d_currency_code.
   - No float, no bare timestamp, booleans NOT NULL DEFAULT.
   - `text` only with `unbounded:` and a `<col>_language_id`.
7. **Comments:**
   - Table: `COMMENT ON TABLE` starting with `[soft-delete]`, `[hard-delete]`, `[append-only]` or `[derived]` (dw only).
   - Column: `[Public|Internal|Personal|Sensitive] description; null: reason`. `null:` is required when nullable.
   - Sensitive columns are bytea or `*_hash` / `*_token` / `*_masked` / `*_last4`.
   - `id` and audit columns are commented automatically.
8. **Enumerations:** `SELECT ref.create_lookup('ref.x', 'purpose');` then `SELECT ref.add_lookup_value('ref.x', 'code', 'English label', sort);`. No free-text enums.
9. **Seed/DDL scripts** start with `SET app.current_user_id = '1';` (the system actor).
10. **Negative tests** use `qa.expect_error('label', $q$<sql>$q$, '<constraint or trigger name>')`. Wrap tests in `DO $test$ ... $test$`.

## Milestone workflow (each new chat)
1. Read this file, `docs/milestones.md`, the milestone's section in `docs/reference/Talentra_Milestone_Plan.md`, and the relevant parts of `docs/00_decisions.md`.
2. Build the deliverables. Add `tests/<area>/mNN_*.sql`.
3. Run `.\run.ps1 gate MNN` until PASS, then `.\run.ps1 test -Evidence`.
4. Update `docs/milestones.md` (Defined, Tested, times). Verified is ticked by a human reviewer.
5. Update "Current state" and append to the "Handoff log" below (at most 6 lines: built, decisions, open issues).
6. Commit `MNN: <summary>` with a green suite. Push when the user says so.

## Current state
- **Done:** M1-M20. Gate M20 PASS (25/25 files). Seed validated at full laptop scale. Tags `phase1`, `phase2`, `core-v1`, `phase4` (pushed to origin up to M18).
  - Phase 1 AI pre-review: `docs/phase1/review.md`. Human reviewer sign-offs are still open.
- **Environment changes made in M19:** tablespace `talentra_data` on `D:\talentra_pg`; `pg_wal` moved to `D:\talentra_pg_wal` (junction from the data dir); server tuned (shared_buffers 4GB, effective_cache_size 16GB, work_mem 32MB, maintenance_work_mem 1GB, max_wal_size 8GB, random_page_cost 1.1, track_io_timing, pg_stat_statements) and restarted.
- **Seeded database:** `talentra_seed` (11 GB): 1M profiles, 100K jobs, 5M applications, 9.9M status history rows. Rebuild with `.\run.ps1 seed -Scale laptop` (~83 min) or `-Scale rehearsal` (1 min). `seed/90_validate.sql` (33 checks) can be rerun on its own.
- **Next:** Phase 5 continues.
  - **M20 queries:** done. `queries/Q01-Q13`, `perf/run_queries.ps1` (run against `talentra_seed`), baseline `perf/results/baseline_laptop.csv`, report `docs/phase5/m20_queries.md`. Slowest: Q05 name substring 62 ms, Q08 company jobs with counts 60 ms; Q09 skill match is the degradation candidate.
  - **M21 performance:** `perf/index_experiments.ps1` drafted (one index per module, drop/measure/recreate). Not yet run; check every index name exists first. Then partitioning note and extrapolation to 10M/100M.
  - **M22 security:** PII notes, threat model, extend RLS to other Personal tables, retention purge job.
  - **M23:** backup/restore timing (pg_dump -Fd -j to D:), security note, Gate 2.
- **Rules learned:**
  - Keep constraint and index names at 62 bytes or less (lint).
  - FKs into `job.application` are composite `(application_id, candidate_profile_id)`.
  - After DDL changes, run `run.ps1 dict`, commit `dictionary/*.csv`, regenerate the phase ERDs, and redraft the phase docs (`tools/draft_design_docs.py`).
  - When a BEFORE trigger and a CHECK/NOT NULL can both fire, the trigger runs first. Leave NULL/shape errors to the constraint.
  - Active app_user rows need `login_email` or `login_phone`.
  - Comment tags drive grants: `[integration-write]`, `[api-write]`.
  - RLS tests: `SET LOCAL ROLE talentra_app` inside the test (superuser bypasses RLS); grant the qa harness to the role inside the test (it is rolled back).
  - `run.ps1` prints with Write-Host, so pipe filters don't work. Capture with `*>&1 | Out-String`, or run with `-Evidence *> $null` and read the evidence file.
  - Long scripted edits: write the Python to the scratchpad and run it; inline Bash heredocs with mixed quotes have failed.
  - Seed SQL: `make_interval`, `chr` and date arithmetic need `int`, not `bigint`; `generate_series` over bigint params yields bigint. `seed.sync_sequences()` after any `OVERRIDING SYSTEM VALUE` load.
  - Long loads: run in the background and do not poll in a loop; the full seed takes ~83 min.
- **Open:**
  - Docket Sections 8 (KPIs), 10 (RTO) and 12 are missing.
  - Reviewer sign-offs (all phases); D31 deviation needs reviewer acceptance.
  - F4.

## Handoff log
- **M1 (2026-10-15):**
  - Built: PG18 decision; `ddl/00-07,99`; `run.ps1`; harness + catalog lint (self-tested against deliberately bad objects); dictionary/ERD export; reserved-word checker; docs 00/01/02 and the milestones board.
  - Key choices: `ref` schema (not mdm), varchar lowercase email (not citext), lookups referenced by code, actor FKs and append-only guards applied centrally by `99_finalise` from the comment contract.
- **M2-M3 (2026-10-15):**
  - Built: `docs/phase1/entities.md` (96 entities), `docs/phase1/relationships.md` (153 FKs, all with ON DELETE and reasons), `docs/erd/phase1.mmd` (rendered from the relationship table), `tools/design_docs.py` (doc validator + ERD renderer), `ddl/10_ref.sql` (user_status, organisation_status), `ddl/15_stubs.sql` (app_user with system actor id 1, organisation). Tests: `tests/docs/m02_*.ps1`, `m03_*.ps1`, `tests/constraints/m03_stubs.sql`.
  - Decisions D9-D11 in `00_decisions.md`. The m01 test now creates real actors, because actor FKs exist from M3. `run.ps1` sets the child process WorkingDirectory.
  - Open: Verified ticks for M1-M3 (reviewer C).
- **M4-M5 (2026-10-15):**
  - Built: `ddl/10_ref.sql` (32 lookups, geography, currency, skills, education, industry, roles, identifier types, seed rows), `20_profile.sql` (24 tables), `30_jobs.sql` (20 tables + transition seed); `ref.label_for()` helper; `dictionary/*.csv`; `docs/erd/phase1_generated.mmd`; `docs/phase1/design.md`.
  - Tests: `m04_columns.sql`, `m05_design_vs_catalog.ps1`. m05 proves the docs match the catalog both ways and that the committed dictionary is fresh.
  - Decisions D12-D14. FKs declared in M4. Cross-module links added later: profile_view_event -> ledger debit (M14), candidate_project -> gig assignment (M10).
- **M6 (2026-10-15):**
  - Built: the M6 sections of `ddl/10_ref.sql`, `20_profile.sql` and `30_jobs.sql`:
    - unique and check constraints, composite FKs and indexes (partial index on open/published/live jobs, trigram, full text);
    - `trg_application_status_transition` + `trg_application_status_history`;
    - **`job.application` hash-partitioned on candidate_profile_id, 32 partitions (D5)**; children carry `candidate_profile_id` (D15).
  - Tests: `m06_phase1.sql` (41 checks: Milestone Plan 1-9, 15+ extra rejections, full pipeline, partitioning). Docs: `docs/phase1/signoff.md`, `docs/02_compliance_table.md` (environment doc renamed to `04_environment.md`, D16).
  - Harness and lint: `qa.expect_error` maps partition index names to parent constraints; new lint rule "RG1 truncated name"; dictionary `references_to` is deterministic.
- **Phase 1 AI pre-review (13:07):** the catalog review found that an application could attach another candidate's resume (fixed with a composite FK) and 15 unindexed FKs on large tables (fixed). Open: F3, F4.
- **M7-M10 (2026-10-15):**
  - Built:
    - `ddl/40_admin.sql`: credentials, roles/permissions, effective-dated user_role, consent, block_list, audit trail + `audit.log_event`, audit triggers.
    - `45_org.sql`: account, organisation extension, hierarchy cycle guard, locations, encrypted identifiers via `org.add_identifier`, verification, account admins, recruiter_mapping + `org.current_recruiter_organisation`.
    - `50_gig.sql`: worker profile, offerings, rates, availability, requests, applications with one-way decisions and blacklist, assignments with B35 exclusion, handoff, integration-only earnings, lists, ratings.
  - Docs: `docs/phase2/*`, `docs/erd/phase2_*.mmd`, `phase2_generated.mmd`. Tools: `tools/draft_design_docs.py`; `design_docs.py` takes comma-separated entity lists.
  - Tests: m07/m08 docs, m10 admin/org/gig (65 checks). Decisions D17-D21.
- **M11-M14 + core gate (2026-10-15):**
  - Built:
    - `ddl/60_lic.sql`: licence, seat (limit trigger with licence-row lock), registered_device, login_session, login_attempt, session_revocation; `app.start_session` / `end_session` / `revoke_session` / `revoke_device` / `expire_idle_sessions`.
    - `65_src.sql`: sourcing_request with consultant-open/role/decider trigger; sourcing_shortlist via `job.shortlist`; outreach batch/recipient with block check.
    - `70_billing.sql`: plans, entitlements, subscriptions with no-overlap exclusion, renewal, cancellation, payment orders, idempotent webhook events, invoices, refunds with cap trigger, wallet, append-only ledger with `post_ledger_entry`, credit consumption, download history + `record_profile_download`; the profile view event links its debit.
  - Tests: m11/m12 docs, m14 lic/src/billing (62 checks), concurrency (20 logins → 3 sessions, 17 audited rejections).
  - Docs: `docs/phase3/*`, `docs/02_compliance_table.md` rows 9-10, `docs/11_coverage_gap_register.md`. Decisions D22-D25.
- **M15-M18 (2026-10-15):**
  - Built:
    - `ddl/80_notif.sql`: preferences (user, notification, job alert), notifications as label keys, monthly-partitioned `notification_delivery` + `ensure_delivery_partitions` + global provider receipts, community, FAQ, tickets.
    - `85_access.sql`: RLS on job_requirement, candidate_profile, candidate_contact, application via SECURITY DEFINER actor helpers; F3 interviewer trigger.
    - `90_dw.sql`: dim_date, dim_organisation (SCD1), dim_candidate and dim_job_requirement (SCD2), fact_application (job + gig), agg_daily_funnel, etl_watermark, `dw.refresh_marts()` (idempotent), `dw.v_funnel_by_category`.
  - Harness: `qa.explain_lines`. Base: sequence USAGE grants.
  - Tests: m15/m16 docs, m18 access (23), notif (16), dw (14). Decisions D26-D29.
- **M19 (2026-10-15/16):**
  - Built: `seed/00-90` (server-side SQL generator, deterministic), `distributions.yaml`, `data_quality_issues.md`, `run.ps1 seed -Scale rehearsal|laptop [-Database] [-Tablespace]`; tablespace and WAL on D:, server tuned.
  - Results: rehearsal 33/33 in 1 min; laptop scale 33/33 (1M/100K/5M, funnel 30.00/12.01/4.00/2.99%, 2.68% phone duplicates, 0 orphans over 817 FKs, 300/300 gig overlaps rejected), 11 GB, 83 min. Evidence `docs/evidence/seed_laptop_20261016.txt`.
  - Decisions D30 (SQL generator, not Faker), D31 (deviation: replica-mode load re-proved by validation), D32 (placement on D:).
- **M20 (2026-10-16):** 13 queries with name/kind/mode headers; runner measures 30 runs of EXPLAIN (ANALYZE, BUFFERS) in BEGIN/ROLLBACK; baseline + plans committed; `tests/docs/m20_query_set.ps1` checks completeness. Report includes the 33/33 seed validation against Section 5. Observations for M21: employer-side queries fan out over 32 partitions (D5 trade-off); Q09 relies on LIMIT.
