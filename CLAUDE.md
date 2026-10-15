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
.\run.ps1 dict               # dictionary/columns.csv, tables.csv, docs/erd/generated.mmd
.\run.ps1 erd -Schemas ref,profile,job -Out docs/erd/phase1_generated.mmd
python tools/reserved_words.py docs/phase1/entities.md
```

## Layout
- `ddl/NN_*.sql`: applied in order.
  - Already present: `00` extensions/schemas/roles, `05` domains, `06` base functions, `07` ui_label/language/ui_translation, `99_finalise` (always last).
  - Planned slots: `10_ref`, `15_stubs`, `20_profile`, `30_jobs`, `40_admin`, `45_org`, `50_gig`, `60_lic`, `65_src`, `70_billing`, `80_notif`, `85_access`, `90_dw`.
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
- **Done:** M1 (gate M1 PASS: 72 checks, 0 lint violations).
- **Next:** M2 + M3. Entity and relationship tables in `docs/phase1/`, `docs/erd/phase1.mmd`, `ddl/15_stubs.sql` (admin.app_user with system user id 1, org.organisation).
- **Open:** docket Sections 8, 10 and 12 are missing (ask the organisers); Verified ticks need reviewer initials; pg_stat_statements and memory settings are not yet applied (needs a service restart, see `docs/02_environment.md`).

## Handoff log
- **M1 (2026-10-15):**
  - Built: PG18 decision; `ddl/00-07,99`; `run.ps1`; harness + catalog lint (self-tested against deliberately bad objects); dictionary/ERD export; reserved-word checker; docs 00/01/02 and the milestones board.
  - Key choices: `ref` schema (not mdm), varchar lowercase email (not citext), lookups referenced by code, actor FKs and append-only guards applied centrally by `99_finalise` from the comment contract.
