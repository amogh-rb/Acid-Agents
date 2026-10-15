# Talentra: Milestone Delivery Plan (docket M1-M23)

**Team:** A, B, C. **Start:** 11:45 IST. **Core gate:** 14:30 IST (Phases 1-3, M1-M14, built, verified and tested).
**Companion to:** `Talentra_Merged_Build_Plan.md`. That file holds the design decisions and module specs; this file holds the order of work and the definition of done.

---

## 1. How every milestone is closed

A milestone is **done** only when all three checks hold. Nobody starts the next milestone of the same module until the gate passes.

| Check | Meaning | Evidence |
|---|---|---|
| **Defined** | The deliverable file exists, in the agreed path and format, with every required field filled | File in `docs/` or `ddl/` committed to git |
| **Verified** | Someone other than the author walks the milestone checklist and ticks it | Reviewer initials + time in `docs/milestones.md` |
| **Tested** | The automated gate for that milestone passes on a **fresh** database | `.\run.ps1 gate Mnn` prints `PASS` |

**Gate mechanics** (built in M1, used by every milestone after):
- `run.ps1 up` drops and recreates `talentra`, then applies every `ddl/*.sql` in order with `ON_ERROR_STOP=1`.
- `run.ps1 gate Mnn` runs `up`, then every test file tagged up to that milestone (`tests/**/mNN_*.sql`), and prints PASS/FAIL per file.
- Each test file is a `DO` block. A **negative test** tries a violating statement and passes only if the expected named constraint or trigger fires (the gate checks the constraint name in the error). A **positive test** inserts valid rows and asserts the counts.
- `run.ps1 test` = gate for every milestone done so far. Run it before every git commit; a red suite is never committed.
- `docs/milestones.md` is the status board: one row per milestone with owner, Defined / Verified / Tested ticks, and the time each passed.

**Base that every milestone builds on** (set up in M1, never rebuilt):
- domains (`d_person_name`, `d_email`, `d_phone_e164`, `d_money`, `d_pct`, `d_lat`, `d_lng`);
- the audit column set and `set_updated_at()` trigger;
- the lookup + UI-label pattern;
- the append-only guard trigger function `audit.forbid_update_delete()`;
- the catalog lint (naming, reserved words, comment tags, money/currency, float ban, `timestamptz`, FK coverage, audit columns);
- the dictionary and Mermaid ERD export from `pg_catalog`.

Because the lint runs inside every gate, Rules 1, 3, 5, 6 and 8 are re-checked on every milestone, not just at the end.

---

## 2. Timeline at a glance

| Time (IST) | Milestones | A | B | C |
|---|---|---|---|---|
| 11:45-12:05 | **M1** | DB, extensions, schemas, domains | Decisions doc, module list, assignments | `run.ps1`, lint, dictionary export, gate runner |
| 12:05-12:20 | **M2** | Master data + Profile entities | Jobs and Applications entities | Review both; reserved-word check |
| 12:20-12:35 | **M3** | Profile relationships | Jobs relationships | Review; Mermaid ERD |
| 12:35-12:55 | **M4 + M5** | ref + Profile columns as DDL with comments | Jobs columns as DDL with comments | Review; lint fixes; dictionary export |
| 12:55-13:15 | **M6** | Profile keys/constraints + tests | Jobs keys/constraints, transition trigger + tests | Review; **Phase 1 sign-off** |
| 13:15-13:50 | **M7-M10** | Administration | Organisation and account | Gig marketplace |
| 13:50-14:25 | **M11-M14** | Licences, seats, devices, sessions | Sourcing and consultant requests | Subscriptions, wallet, payments, downloads |
| **14:25-14:30** | **Core gate** | Fresh `run.ps1 test`, all green, tag `core-v1` | | |
| 14:30 onward | M15-M23 | Shared items, security | Notifications, seed | Analytics, queries, performance |

**Slip rules:**
- **M6 must pass by 13:20.** If not, all three fix Phase 1 and Phases 2-3 lose the time evenly. A design that fails its own tests is worse than a missing module.
- **Inside Phases 2 and 3,** each member's four milestones run back to back on one module. If a member is late at the column milestone, ship the Tier 1 tables and their **constraint tests** first, and record any Tier 2 tables in the gap register.
- **Never trade tests for tables.** A module without passing negative tests does not count as done.

---

## 3. Phase 1: Foundation (whole team)

### M1: Identify and fix the DB provider (B1-B3), plus the build base
**Slot:** 11:45-12:05 | **Owner:** all (A: database, B: docs, C: tooling)

**Defined:**
- `docs/00_decisions.md`: engine (PostgreSQL 18, with reasons), PK type, naming, schemas, delete classes, gig decision headline, central vs secondary workflows.
- `docs/01_module_list.md`: 11 modules + optional stretch, owner per module, every docket Section 4 domain mapped to one module.
- `ddl/00_extensions_schemas.sql`, `ddl/05_domains.sql`, `ddl/06_base_functions.sql` (`set_updated_at`, `audit.forbid_update_delete`).
- `run.ps1` (up / test / gate), `tools/reserved_words.py`, `tools/export_dictionary.sql`, `tests/lint/*.sql`.
- `docs/milestones.md` status board.

**Verified:**
- Every Section 4 domain (Tier 1 and 2) appears in exactly one module.
- `postgresql.conf` settings recorded (shared_buffers, work_mem, maintenance_work_mem, pg_stat_statements).

**Tested (`gate M1`):**
- `run.ps1 up` creates the DB from nothing with encoding UTF8.
- Domain tests: `'Foo@X.com'::d_email` fails; `'+919840012345'::d_phone_e164` passes and `'98400 12345'` fails; `-1::d_pct` fails.
- An update on a dummy table with `forbid_update_delete` raises.
- The lint runs and passes on the empty schema.

### M2: Entities for Profile and Jobs and Applications (B4-B7)
**Slot:** 12:05-12:20 | **Owner:** A (Profile + Master data), B (Jobs), C reviews

**Defined:** `docs/phase1/entities.md`, one row per entity:

| entity | schema | module | purpose (one line) | tier | delete class (soft / hard / append-only) | owner |
|---|---|---|---|---|---|---|

Start from the lists in section 5 of the merged plan. Include the 4 stubs (`app_user`, `organisation`, `job_requirement`, `candidate_profile`) and all `ref` lookups.

**Verified (C ticks):**
- Every Profile and Jobs domain from the module table (docket Section 7) has at least one entity.
- No two entities hold the same fact.
- Shared ownership is settled: shortlist belongs to Jobs, bookmark history to Profile.
- Every enumeration in the design has its own `ref` lookup.

**Tested (`gate M2`):** `reserved_words.py docs/phase1/entities.md` finds no reserved or plural names.

### M3: Relationships for Profile and Jobs and Applications (B8-B11)
**Slot:** 12:20-12:35 | **Owner:** A, B; C reviews

**Defined:**
- `docs/erd/phase1.mmd` (Mermaid `erDiagram`) with cardinality on every line.
- `docs/phase1/relationships.md`, one row per relationship:

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|

**Verified:**
- Every many-to-many has a junction table (candidate_skill, job_requirement_skill and so on).
- `RESTRICT` by default, `CASCADE` only for owned children, and each CASCADE is justified.
- Every optional relationship has a reason in the table.
- No relationship leads to a table outside Phase 1 except the four stubs.

**Tested (`gate M3`):** `ddl/15_stubs.sql` applies, so later FKs have targets; the stub tests insert a system user and organisation.

### M4: Columns for Profile and Jobs and Applications (B12-B15)
**Slot:** 12:35-12:50 | **Owner:** A, B; C reviews

**Defined:**
- `ddl/10_ref.sql`, `ddl/20_profile.sql` and `ddl/30_jobs.sql` with **columns only**: types, domains and NOT NULL. Keys come in M6.
- Every column carries `COMMENT ON COLUMN ... IS '[Class] null: reason'`, or `'[Class]'` when NOT NULL.
- The lookup seed rows that later milestones depend on: `application_status`, `application_status_transition`, `disclosure_code`, `job_status`, `publish_state`, `language`, `currency`, `country`.

**Verified:**
- Unknown vs not applicable uses `disclosure_code` (Rule 5); there are no sentinels.
- Unbounded `text` appears only for the job description and resume body.
- User-entered text carries a `<col>_language_id`.
- Every money column has `<col>_currency_code`.

**Tested (`gate M4`):** the lint passes. It checks that every column has a class tag, every nullable column has a reason, there are no `float`/`real`, no bare `timestamp`, and money columns are paired with a currency column.

### M5: Design for Profile and Jobs and Applications (B16-B19)
**Slot:** 12:50-12:55 | **Owner:** C (export), A and B confirm

**Defined:**
- `dictionary/columns.csv` exported from the catalog.
- `docs/erd/phase1_generated.mmd` generated from the catalog.
- A short `docs/phase1/design.md` that explains the profile and pipeline model in 10 lines.

**Verified:** The generated ERD matches the hand-drawn M3 ERD. Every difference is either fixed or recorded.

**Tested (`gate M5`):** the dictionary export row count equals the number of columns in `information_schema`, and no export row has an empty class or (for nullable columns) an empty reason.

### M6: Keys and constraints for Profile and Jobs and Applications (B20-B23)
**Slot:** 12:55-13:15 | **Owner:** A (Profile), B (Jobs); C reviews and signs off

**Defined:**
- PKs, FKs (with ON DELETE as in M3), unique constraints, CHECK constraints and the Phase 1 indexes, all named by convention.
- `trg_application_status_transition` and an append-only guard on `application_status_history`.
- A partial index on open, published, non-deleted jobs.
- `tests/constraints/m06_phase1.sql`.
- `docs/phase1/signoff.md`.

**Verified:** Every check in the Rule 2 list is present:
- date ranges;
- salary min ≤ max;
- experience min ≤ max;
- disclosure code ↔ NULL amounts;
- a unique application per candidate and job;
- unique lowercase contact email.

**Tested (`gate M6`)**, each failing with its named constraint:

| # | Negative test | Must fail with |
|---|---|---|
| 1 | salary_min 90000, salary_max 50000 | `ck_job_requirement_salary_range` |
| 2 | `not_disclosed` with salary_min 0 | `ck_job_requirement_salary_disclosure` |
| 3 | Education ends before it starts | `ck_candidate_education_date_range` |
| 4 | Duplicate application for the same candidate and job | `uq_application_candidate_profile_id_job_requirement_id` |
| 5 | Status `applied` → `joined` | `trg_application_status_transition` |
| 6 | UPDATE of a status-history row | `forbid_update_delete` |
| 7 | Free-text status | FK to `ref.application_status` |
| 8 | Duplicate contact email in a different case | `uq_candidate_contact_email` |
| 9 | Delete a job requirement that has applications | FK RESTRICT |

Positive test: a candidate with education, experience and skills applies to a published job and moves through applied → shortlisted → interviewed → offered → joined, with 5 history rows.

**Exit:** C signs `docs/phase1/signoff.md` (B23). Commit and tag `phase1`.

---

## 4. Phase 2: Individual modules (13:15-13:50)

Each member runs M7 → M8 → M9 → M10 on one module, about 8 / 8 / 9 / 10 minutes. M7-M9 are the same Defined / Verified checks as Phase 1, applied to one module (entity rows, relationship rows, columns with comment tags; lint must pass). M10 adds the module's own constraint tests. **Review pairs:** A reviews B, B reviews C, C reviews A.

### Member A: Administration (B24, B27, B30, B33)
- **Entities:**
  - users and access control: app_user (extends the stub), user_credential, app_role, permission, app_role_permission, user_role;
  - consent_record;
  - block_list;
  - audit.audit_event, audit.error_log.
- **Key relationships:** user→role (effective-dated), role→permission, block_list→blocker and exactly one blocked target, audit_event→actor.
- **Constraints:**
  - one credential per user, holding the hash only;
  - `ck_block_list_single_target` (exactly one of user / organisation);
  - unique block pair;
  - `audit_event` is append-only (grants + trigger);
  - `audit.log_event()` function.
- **`gate M10` tests:**
  - second credential for a user → fails;
  - block row with both targets or neither → fails;
  - UPDATE or DELETE of an audit row → fails;
  - `log_event` inserts a row;
  - overlapping user_role periods → fails, if effective dating uses an exclusion.

### Member B: Organisation and account (B25, B28, B31, B34)
- **Entities:** organisation (extends the stub), organisation_location, organisation_identifier, verification, account, account_administrator, recruiter_mapping.
- **Constraints:**
  - organisation can't be its own parent, with a cycle-guard trigger;
  - organisation_identifier: `value_encrypted bytea`, unique `value_hash`, regex in `ref.identifier_type`;
  - **`ex_recruiter_mapping_valid_range`** (B34).
- **`gate M10` tests:**
  - a recruiter mapped to two companies in overlapping periods → fails;
  - a back-to-back mapping → passes;
  - an organisation that is its own parent → fails;
  - a 3-level cycle → fails;
  - a duplicate identifier hash → fails.

### Member C: Gig marketplace (B26, B29, B32, B35)
- **Entities:**
  - requests and workers: gig_request, gig_worker_profile, gig_service_offering, gig_charge_rate, gig_availability;
  - applications and assignments: gig_application, gig_assignment;
  - external fulfilment: gig_fulfilment_handoff, gig_earning_reference;
  - lists and ratings: gig_requester_worker_list, gig_rating.
- **Constraints:**
  - gig window end ≥ start;
  - a pricing model check (fixed price, or a rate plus unit);
  - **`ex_gig_assignment_worker_window`** for active and handed-off assignments (B35);
  - unique handoff external reference and idempotency key;
  - rating between 1 and 5, one per completed assignment;
  - earnings are read-only for the app role.
- **`gate M10` tests:**
  - overlapping active assignments for one worker → fails;
  - the same overlap where one assignment is cancelled → passes;
  - a duplicate handoff idempotency key → fails;
  - a rating of 6 → fails;
  - a second rating for the same assignment → fails;
  - a gig window that ends before it starts → fails.

**Phase 2 exit (13:50):** `run.ps1 test` is green on a fresh DB. Commit and tag `phase2`.

---

## 5. Phase 3: Individual modules (13:50-14:25)

Same rhythm: M11 entities, M12 relationships, M13 columns, M14 keys and constraints plus tests.

### Member A: Licences, seats, devices and sessions (B36, B39, B42, B45)
- **Entities:** licence, licence_seat, registered_device, login_session, login_attempt, session_revocation.
- **Constraints:**
  - `ck_licence_max_users_positive`, `ck_licence_max_devices_per_user_positive`;
  - unique licence/user seat;
  - unique user/device fingerprint hash;
  - session end ≥ start;
  - a partial index on active sessions.
- **Mechanism:** `app.start_session(user, device)`:
  - locks the seat row `FOR UPDATE` and counts active sessions;
  - inserts the session, **or** writes `login_attempt` + an audit row `DEVICE_LIMIT_EXCEEDED` and **returns** a rejection;
  - `app.end_session`, `app.revoke_session` (audited) and `app.expire_idle_sessions()` release sessions.
- **`gate M14` tests:**
  - with a limit of 2, a third login is rejected and audited;
  - after logout, a login succeeds again;
  - a revoked session doesn't count and the revocation is audited;
  - `max_devices_per_user = 0` → fails;
  - **concurrency:** `tests/concurrency/m14_device_limit.ps1` starts 20 parallel `psql` logins with a limit of 3 and asserts exactly 3 active sessions and 17 audited rejections.

### Member B: Sourcing and consultant requests (B37, B40, B43, B46)
- **Entities:** sourcing_request, sourcing_shortlist (references the Jobs shortlist), outreach_batch, outreach_recipient.
- **Constraints:**
  - the decision columns must agree with the status (decided_by and decided_at are set when accepted or declined);
  - the decline reason is required when declined;
  - **`trg_sourcing_request_consultant_open`** (B46);
  - unique batch idempotency key;
  - unique recipient per batch;
  - a trigger rejects recipients who blocked the sender.
- **`gate M14` tests:**
  - a consultant request on a job not open to consultants → fails;
  - the same request on an open job → passes;
  - declined without a reason → fails;
  - a duplicate batch key → fails;
  - outreach to a candidate who blocked the sender → fails.

### Member C: Subscriptions, wallet, payments and download history (B38, B41, B44, B47)
- **Entities:**
  - plans and subscriptions: plan, plan_entitlement, subscription, subscription_renewal, subscription_cancellation;
  - payments: payment_order, payment_event, invoice, refund;
  - wallet: wallet, wallet_ledger_entry, credit_consumption;
  - downloads: profile_download_event.
- **Constraints:**
  - **`ex_subscription_licence_period`** (excluding cancelled subscriptions);
  - `ck_wallet_balance_non_negative`;
  - the ledger is append-only, and corrections go through `reverses_entry_id`;
  - unique (gateway, gateway_event_id);
  - unique idempotency keys on order and ledger;
  - refund ≤ paid amount;
  - every money column paired with a currency;
  - `billing.post_ledger_entry()` locks the wallet row;
  - each download event references its ledger debit.
- **`gate M14` tests:**
  - overlapping subscriptions on a licence → fail;
  - the same overlap where one is cancelled → passes;
  - UPDATE of a ledger row → fails;
  - a correction posted as a reversing entry → passes and the balance reconciles;
  - a debit that would make the balance negative → fails;
  - a duplicate webhook event → fails;
  - a refund larger than the payment → fails;
  - a download without a ledger entry → fails.

---

## 6. Core gate (14:25-14:30)

| Check | Command / evidence |
|---|---|
| Fresh build | `run.ps1 up` on an empty server applies all DDL with no errors |
| Full suite | `run.ps1 test`: lint + M1-M14 tests, all PASS, output saved to `docs/evidence/core_gate_<time>.txt` |
| Dictionary and ERD | `export_dictionary.sql` regenerated; one Mermaid ERD per phase |
| Status board | `docs/milestones.md` shows M1-M14 Defined / Verified / Tested, each with reviewer initials |
| Compliance | `docs/02_compliance_table.md` filled for rule groups 1-10 and the reserved-word check, with every deviation recorded |
| Gap register | `docs/11_coverage_gap_register.md` lists every Tier 1/2 element not yet built and why |
| Release | `git tag core-v1` |

What you can show the panel at 14:30:
- Phase 1-3 schema built from scratch in one command.
- Every rule from the docket's rule groups 2, 9 and 10 proven by a failing insert with a named constraint.
- The device limit holding under 20 concurrent logins.
- A dictionary that cannot drift from the schema.

---

## 7. After the core gate: Phases 4 and 5 (M15-M23)

The same definition of done applies. Times assume work continues after 14:30. If your event ends at 15:00, do the **bold** items first.

| Milestone | Owner | Deliverable | Done when (tested) |
|---|---|---|---|
| **M15-M18 shared items (B50, B53, B56, B59)** | A | RLS policies, group roles, `SET LOCAL app.current_user_id` | `tests/access/m18_*.sql`: recruiter sees only their company's jobs; consultant sees only open jobs; blocked party sees zero rows of the blocker's profile; recruiter INSERT on candidate_profile fails |
| M15-M18 notifications (B48, B51, B54, B57) | B | Preferences, monthly-partitioned `notification_delivery`, thin community/FAQ/tickets | Duplicate provider message id fails; a row lands in the correct monthly partition; detaching a partition works |
| M15-M18 analytics (B49, B52, B55, B58) | C | `dim_*` (SCD2), `fact_*`, `agg_daily_funnel`, watermark refresh | An SCD2 change closes the old row and opens a new one; a refresh run twice is idempotent (same counts) |
| **M19 seed (B60-B64)** | B (+ shapes from A and C) | `seed/gen_*.py`, `load.sql`, `distributions.yaml`, `data_quality_issues.md` | 10K rehearsal loads through `run.ps1 seed` with zero FK failures; row counts and distributions recorded; full scale or the stated measured scale |
| **M20 queries and validation (B65-B69)** | C, B | Q1-Q12, module queries, EXPLAIN plans, seed validation report | Each query returns its expected shape; the validation report checks seeded data against Section 5 rules |
| **M21 performance (B70-B74)** | C | p50/p95/p99 baseline, index before/after per module, partitioning note, extrapolation | `perf/results/*.csv` exist; the extrapolation names the first query to degrade, using measured inputs |
| M22 security (B75-B79) | A | PII notes, threat model, access and audit test results | `run.ps1 test` includes access and audit tests, all green |
| M23 backup and sign-off (B80-B82) | All | Backup/restore log, security design note, Gate 2 checklist | Restore succeeds, row counts match, time logged against the assumed RTO |

---

## 8. Claude Code prompts per milestone

Run each prompt, then run the gate before committing.

| Milestone | Prompt (with the merged plan and this file attached) |
|---|---|
| M1 | "Implement M1 from Talentra_Milestone_Plan.md section 3: `run.ps1` (up / test / gate Mnn, psql from `C:\Program Files\PostgreSQL\18\bin`, ON_ERROR_STOP), the extensions/schemas/domains/base-function DDL, `tools/reserved_words.py`, `tools/export_dictionary.sql`, `tests/lint/*.sql` and `tests/constraints/m01_base.sql`. Then run `run.ps1 gate M1`." |
| M2-M3 | "Draft `docs/phase1/entities.md`, `relationships.md` and `docs/erd/phase1.mmd` per M2-M3, starting from section 5 of the merged plan. Write `ddl/15_stubs.sql`." |
| M4-M5 | "Write `ddl/10_ref.sql`, `20_profile.sql` and `30_jobs.sql` with columns and COMMENT tags only, plus the lookup seed rows. Run `gate M5` and fix lint failures." |
| M6 | "Add the M6 keys, constraints, transition trigger and append-only guard. Write `tests/constraints/m06_phase1.sql` with the 9 negative tests and the positive pipeline test. Run `gate M6`." |
| M7-M10 / M11-M14 | "Implement <module> through M10 (or M14) per sections 4-5, including its test file, then run the gate." One prompt per member, in their own branch; merge after the review. |
