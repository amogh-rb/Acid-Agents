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
- C: has about 20 GB free; D: has 170 GB. The seed goes in a tablespace on `D:\talentra_pg` (M19).
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
  - Built: `10_ref`, `15_stubs`, `20_profile`, `30_jobs`, `40_admin`, `45_org`, `50_gig`. Planned: `60_lic`, `65_src`, `70_billing`, `80_notif`, `85_access`, `90_dw`.
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
- **Done:** M1-M10 (gate M10 PASS, 13/13 files). Tags `phase1`, `phase2` (local; nothing pushed yet). Phase 1 AI pre-review in `docs/phase1/review.md`; human reviewer C still has to sign `docs/phase1/signoff.md` and tick Verified for M1-M10.
- **Next:** Phase 3, M11-M14 (core gate: `run.ps1 test` all green, then tag `core-v1`). Per module (Milestone Plan section 5):
  - **Licences, seats, devices, sessions** (A): `ddl/60_lic.sql`, schemas `lic` + `app`.
    - Tables: licence (max_users, max_devices_per_user CHECK > 0), licence_seat (unique licence/user), registered_device (unique user/fingerprint hash), login_session, login_attempt (append-only), session_revocation (append-only).
    - `app.start_session` locks the seat row FOR UPDATE, counts active sessions (partial index `ended_at IS NULL`), then either inserts the session or writes login_attempt + `audit.log_event('device_limit_exceeded', ...)` and returns a rejection. Also `app.end_session`, `app.revoke_session` (audited, `session_revoked`) and `app.expire_idle_sessions`.
    - Concurrency test `tests/concurrency/m14_device_limit.ps1`: 20 parallel psql logins with limit 3 -> exactly 3 active sessions, 17 audited rejections. Note: SQL tests roll back, so this one must commit its own data and clean up.
  - **Sourcing** (B): `ddl/65_src.sql`, schema `src`.
    - Tables: sourcing_request, sourcing_shortlist (references job.shortlist), outreach_batch, outreach_recipient.
    - Rules: `trg_sourcing_request_consultant_open` (job.job_requirement.is_open_to_consultant); decision columns consistent with status; decline reason required; unique batch idempotency key; unique recipient per batch; trigger rejects recipients who blocked the sender (admin.block_list, user or organisation).
  - **Subscriptions, wallet, payments, downloads** (C): `ddl/70_billing.sql`, schema `billing`.
    - Tables: plan, plan_entitlement, subscription (`ex_subscription_licence_period` excluding cancelled), renewal, cancellation, payment_order, payment_event (unique gateway + event id), invoice, refund (<= paid), wallet (`ck_wallet_balance_non_negative`), wallet_ledger_entry (append-only, `reverses_entry_id`), credit_consumption, profile_download_event (references its ledger debit).
    - `billing.post_ledger_entry()` locks the wallet row. Add `profile.profile_view_event` -> ledger debit FK (nullable, ALTER).
  - **Docs:** `docs/phase3/<module>_entities.md` / `_relationships.md`. Draft them with `python tools/draft_design_docs.py ddl/60_lic.sql "Licences, seats, devices and sessions" A docs/phase3/lic` after `run.ps1 dict`, then review. Add `tests/docs/m11_*.ps1` / `m12_*.ps1` like m07/m08 (glob phase3). m05 already compares every phase.
  - **Then the core gate:** `docs/02_compliance_table.md` rows 9-10, `docs/11_coverage_gap_register.md` (Tier 1/2 elements not built: notifications, community, tickets, FAQs, analytics come in M15-M18; review findings F3/F4), `run.ps1 test -Evidence`, tag `core-v1`.
- **Rules learned:**
  - Keep constraint and index names at 62 bytes or less (lint).
  - FKs into `job.application` are composite `(application_id, candidate_profile_id)`.
  - After DDL changes, run `run.ps1 dict` and commit `dictionary/*.csv`; also regenerate the phase ERDs.
  - When two CHECKs can fire, PostgreSQL reports the first by name, so isolate the rule in negative tests.
  - Active app_user rows need `login_email` or `login_phone` (tests must supply one).
  - Tables written by an external system: tag the comment `[integration-write]`.
  - Long scripted edits: write the Python to the scratchpad and run it; inline Bash heredocs with mixed quotes have failed.
- **Open:**
  - Docket Sections 8, 10 and 12 are missing (ask the organisers).
  - Reviewer C signatures.
  - pg_stat_statements and memory settings not yet applied (needs a service restart, see `docs/04_environment.md`).
  - Review findings F3 (interviewer belongs to the job's organisation; recruiter mapping now exists, so this can be a trigger) and F4.

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
