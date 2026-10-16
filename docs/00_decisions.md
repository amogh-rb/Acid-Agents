# 00 Decisions (M1: B1-B3)

Source documents: the docket (Sections 1-7), `docs/reference/Talentra_Delivery_Plan.pdf` (design decisions) and `docs/reference/Talentra_Milestone_Plan.md` (order of work and definition of done). Where the two plans differ, the resolution is recorded under section 9.

## 1. DB provider (B1): PostgreSQL 18

PostgreSQL 18.4 is installed on the team laptops. The docket's hardest rules map onto features PostgreSQL has natively and MySQL 8 does not:

| Docket rule | PostgreSQL mechanism | MySQL 8 gap |
|---|---|---|
| No overlapping subscription periods (RG10); no overlapping gig windows per worker (B35); effective-dated recruiter mapping (B34) | `EXCLUDE USING gist` with `btree_gist` on `daterange` / `tstzrange`. PG18 also offers `WITHOUT OVERLAPS` keys | No exclusion constraints. Triggers race under concurrent inserts |
| Privileges enforced in the database: a recruiter sees only their own company's jobs, and a blocked party can't see the candidate | Row-Level Security keyed on `current_setting('app.current_user_id')` | No RLS. Views can be bypassed |
| Soft deletes excluded by default; active sessions counted at 10M scale | Partial indexes (`WHERE deleted_at IS NULL`, `WHERE ended_at IS NULL`); `security_invoker` views | No partial indexes |
| Job search and fuzzy multilingual de-duplication | `tsvector` + GIN; `pg_trgm` | FULLTEXT is weaker; no trigram |
| Analytics marts over 100M applications | Materialized views; declarative range partitioning | No materialized views |
| Append-only audit and ledgers; Sensitive columns | `REVOKE UPDATE, DELETE` + trigger guard; `pgcrypto`; column grants | Possible, with fewer primitives |
| Device limit under concurrent login (B45) | `SELECT ... FOR UPDATE` on the seat row inside one transaction | Also possible (InnoDB) |

- **Extensions:** `btree_gist`, `pg_trgm`, `pgcrypto`. `pg_stat_statements` is installed automatically once it is preloaded (see `04_environment.md`).
- **Database:** UTF8 encoding with ICU collation `und`, so multilingual names sort sensibly. Verified by `gate M1`.

## 2. Keys (RG2)

- **Primary key:** `id bigint GENERATED ALWAYS AS IDENTITY` on every table, constraint `pk_<table>`. The lint checks this.
  - bigint (8 bytes) rather than UUID (16 bytes) keeps the indexes for 100M applications small and their inserts sequential.
  - Public-facing references, where needed, get a separate unique token column.
- **Natural keys** are unique constraints, never primary keys. Examples: email that identifies an account, identifier hash, legacy source id.
- **Foreign keys** are named `fk_<table>_<column>` and always state their actions:
  - The default is `ON UPDATE NO ACTION ON DELETE RESTRICT`.
  - `CASCADE` is used only for owned child rows (for example `candidate_skill`), and the reason goes in the relationship table.
- **Lookup references** use the lookup's `code`. Example: `current_status_code d_code REFERENCES ref.application_status(code)`. Codes are stable and readable, and free text can't get in.
- **Actor FKs:** `created_by` and `updated_by` reference `admin.app_user(id)`. `ddl/99_finalise.sql` adds them to every table, so nobody can forget one. The system actor is `app_user.id = 1`.

## 3. Naming (RG1, RG8)

| Object | Pattern |
|---|---|
| Tables, columns | snake_case, singular table names, no PostgreSQL (R/T/C) or MySQL reserved words |
| Primary key / FK / unique / check / exclusion | `pk_<table>` / `fk_<table>_<col>` / `uq_<table>_<cols>` / `ck_<table>_<rule>` / `ex_<table>_<rule>` |
| Index | `idx_<table>_<cols>`; a unique index that can't be a constraint (for example partial) uses `uq_<table>_<cols>` |
| Trigger | `trg_<table>_<purpose>` |
| View / materialized view | `v_<name>` / `mv_<name>` |
| Partition | Range: `<table>_pYYYY`, `<table>_pYYYYMM`, `<table>_default`; hash: `<table>_hNN` (`job.application_h00..h31`) |
| Analytics | schema `dw`; tables `dim_`, `fact_`, `agg_`, `etl_` (refresh watermarks). These prefixes are not allowed outside `dw` |
| Domains | `d_<kind>` |

Reserved names are avoided by design: `app_user`, `app_role`, `payment_order`, `job_position`, `login_session`, `user_group`. `tools/reserved_words.py` checks the design docs, and the lint checks the catalog.

## 4. Schemas (modules)

| Schema | Module |
|---|---|
| `ref` | Master data: geography, skills, qualifications, every enumeration lookup, UI labels and translations |
| `admin` | Administration (users, credentials, roles, permissions, consent, blocking) |
| `org` | Organisation and account |
| `profile` | Profile |
| `job` | Jobs and Applications |
| `gig` | Gig marketplace |
| `lic` | Licences, seats, devices and sessions |
| `src` | Sourcing and consultant requests |
| `billing` | Subscriptions, wallet, payments and download history |
| `notif` | Notifications, preferences and community |
| `dw` | Analytics layer and reporting marts |
| `audit` | Audit trail, error log, append-only guard |
| `app` | Database API functions for multi-row rules (`app.start_session`, ...) |
| `public` | Domains and generic helpers only (no tables) |
| `qa` | Test harness. Loaded only by `run.ps1 gate`; never in production DDL |

## 5. Standard domains (RG3)

| Domain | Definition |
|---|---|
| `d_person_name` | varchar(150), not blank |
| `d_email` | varchar(254), lowercase, loose format check |
| `d_phone_e164` | varchar(16) `^\+[1-9][0-9]{6,14}$`, plus a `<col>_country_id` column |
| `d_money` | numeric(14,2), plus `<col>_currency_code` or `currency_code` (FK to `ref.currency`) |
| `d_currency_code` | char(3) ISO 4217 |
| `d_pct` | numeric(5,2), 0-100 |
| `d_lat` / `d_lng` | numeric(9,6) WGS84, about 0.11 m. The source (geocoder or user pin) is stated per table |
| `d_code` | varchar(40) lowercase snake_case lookup code |

Other rules:
- **Free text:** varchar(n) with a stated maximum. Unbounded `text` only for content such as job descriptions and resume bodies, with an `unbounded:` reason in the comment and a `<col>_language_id`.
- **Timestamps:** `timestamptz` (UTC) only. Add `source_timezone varchar(64)` where display needs it.
- **Dates:** `date`.
- **Date ranges:** `ck_<table>_date_range CHECK (end_date IS NULL OR end_date >= start_date)`.
- **Booleans:** NOT NULL with a DEFAULT, enforced by the lint.
- **Floats:** banned (lint).
- **Enumerations:** a lookup table built by `ref.create_lookup()`: code, label_key, is_active, sort_order and audit columns. Display text per language is in `ref.ui_translation`. Free-text enumerations are not allowed.
- **UI labels:** `ref.ui_label(label_key)` plus `ref.ui_translation(ui_label_id, language_id, translated_text)`.
  - Fallback: the requested language, then the single default language (`ref.language.is_default`, English).
  - `ref.ui_text()` returns NULL rather than the key, so keys are never displayed.

## 6. The comment contract (RG4-RG6; drives the lint, the dictionary and `99_finalise`)

**Table comment** starts with its delete class:

| Class | Meaning | Added automatically by `99_finalise` |
|---|---|---|
| `[soft-delete]` | `deleted_at timestamptz` (nullable) | Default view `v_<table>` (`security_invoker`) that hides deleted rows |
| `[hard-delete]` | Rows may be deleted (junction rows, lookups not yet referenced) | - |
| `[append-only]` | Insert only. Has `created_at`/`created_by` but no `updated_*` (rows never change) | `trg_<table>_forbid_update_delete`, `trg_<table>_forbid_truncate`, and UPDATE/DELETE/TRUNCATE revoked from `talentra_app` |
| `[derived]` | `dw` only. Rebuilt by the refresh process | - |

**Column comment:**
- Format: `'[Public|Internal|Personal|Sensitive] description; null: reason; unbounded: reason; nofk: reason; nolang: reason'`.
- Use only the markers that apply. `null:` is required on every nullable column (RG5).
- `[Sensitive]` columns must be `bytea` (pgcrypto-encrypted) or `*_hash` / `*_token` / `*_masked` / `*_last4`.

Every business table has `created_at`, `created_by`, `updated_at` and `updated_by`, with defaults `now()` and `current_actor_id()`. `99_finalise` attaches `trg_<table>_set_updated_at`, which also makes `created_*` immutable. The application sets `SET LOCAL app.current_user_id = '<id>'` per transaction. An insert with no actor fails rather than recording a fake one.

**Unknown vs not applicable (RG5):** use disclosure code columns that are tied to NULL amounts by a CHECK, for example `salary_disclosure_code` = `disclosed` | `not_disclosed` | `not_applicable`. No 0, 'NA' or empty-string sentinels.

## 7. Delete classes and retention (RG4)

| Class | Entities |
|---|---|
| Soft delete | candidate_profile, job_requirement, organisation, gig_request, resume_version, app_user |
| Hard delete | junction rows (candidate_skill, job_requirement_skill, ...), lookups not yet referenced |
| Append-only | audit_event, application_status_history, wallet_ledger_entry, payment_event, profile_view_event, profile_download_event, candidate_activity_event, candidate_bookmark_event, login_attempt, notification_delivery. Not partitioned in Phase 1. They are leaf tables (no FK points at them), so monthly range partitioning can be added in M21 without rebuilding any FK; the decision rests on measurements |

**Retention:**
- Deletion on request anonymises Personal columns and sets `deleted_at`.
- A scheduled purge runs after the stated window.
- The inactivity window is stated per entity in the data dictionary (M22).

## 8. Gig decision (headline) and workflows (B2)

**Gig is a separate subsystem (`gig` schema).** It shares identity, master data and analytics dimensions with the core.
- **Why separate:** windows, fixed or rate pricing, one-directional apply, external fulfilment, earnings and ratings all differ from permanent and contract jobs. Folding gigs into `job_requirement` would add many nullable columns and weaken the CHECK constraints.
- **Cost:** pipeline reporting across both needs a union. This is mitigated by `dw.fact_application` (carries a `job_category` dimension and is loaded from both) and `v_all_application`.

**Central workflows** are modelled with constraints and tests, because they carry money, privacy, or pipeline integrity:
- registration, login and profile;
- job posting, search, application and status tracking;
- employer verification;
- consultant sourcing requests;
- blocking;
- wallet and credit consumption;
- gig apply, assignment and handoff;
- licences and device-limited sessions.

**Secondary workflows** are modelled thinly (entities and keys, few cross-entity invariants), because they are append-mostly or content-only:
- questionnaire authoring (structure only);
- bulk outreach content;
- notifications and job alerts;
- support tickets and FAQs;
- community posts.

**Out of scope, noted:** sub-roles inside an employer organisation. Extension path: add an `organisation_id` scope to `admin.user_role` plus new permission rows; no other table changes.

## 9. Deviations and resolutions (feed `02_compliance_table.md`)

| # | Topic | Decision | Reason / risk |
|---|---|---|---|
| D1 | Master-data schema name | `ref` (the Delivery Plan said `mdm`) | The Milestone Plan and its test names use `ref.*`. Naming only |
| D2 | Email type | `varchar(254)` + lowercase CHECK (the Delivery Plan said `citext`) | The docket says "stored in lowercase". Once lowercase is stored, a normal unique index is already case-insensitive. citext would hide case instead of rejecting it |
| D3 | Engine version | PostgreSQL 18 (the Delivery Plan said 16/17) | This version is installed; it is a superset for every feature used |
| D4 | `updated_at`/`updated_by` on append-only tables | Omitted | Rows never change; the columns would always equal `created_*`. Documented in RG4 |
| D5 | Partitioning `job.application` | **Decided in M6: HASH (candidate_profile_id), 32 partitions `application_h00..h31`.** PK `(id, candidate_profile_id)`; `uq_application_candidate_profile_id_job_requirement_id` still holds (it contains the key). Every FK into application is composite `(application_id, candidate_profile_id)`: application_answer, application_status_history, interview, offer, joining; job_position uses `(filled_by_application_id, filled_by_candidate_profile_id, job_requirement_id)` | Done now because six tables reference application and would all need rebuilding later.<br>**Why candidates, not jobs, as the key:** applications per job are Zipf-skewed (hot partitions), while applications per candidate are even.<br>**Why not range on applied_at:** the one-per-candidate-per-job key would then have to include applied_at and would stop being enforced.<br>**Cost:** recruiter queries by job probe all 32 partition indexes (`idx_application_job_requirement_id`). M21 measures this and states the 100M projection. At 100M rows each partition holds about 3.1M.<br>**Risk:** id is unique by the identity sequence, not by a constraint on id alone (GENERATED ALWAYS blocks manual ids). Unique violations report the partition index name; the harness maps it to the parent constraint |
| D6 | Analytics tables (`dw`) | No audit columns; `[derived]` class | Rows are rebuilt from operational tables; lineage via `etl_` watermarks |
| D7 | Milestone Plan references `Talentra_Merged_Build_Plan.md` | The Delivery Plan PDF is used as that document ("section 5 of the merged plan" = Delivery Plan section 4) | The merged file was not available |
| D9 | Status FK column names | `application.application_status_code`, `from_application_status_code`, `to_application_status_code` (the Delivery Plan said `current_status_code`, `from_code`, `to_code`) | RG1: an FK is the referenced table name + `_id`/`_code`, optionally with a role prefix. `tools/design_docs.py` enforces it |
| D10 | Lookup table for unknown vs not applicable | `ref.disclosure` (the Milestone Plan said `disclosure_code`); columns are `<x>_disclosure_code` | A table named `*_code` would break the FK naming rule above |
| D11 | Status lookups needed by the stubs | `ref.user_status` and `ref.organisation_status` are created in `ddl/10_ref.sql` at M3 | The stubs (15) need them; M4 extends `10_ref.sql` |
| D12 | Money precision | `d_money` = numeric(14,2) for every currency; `ref.currency.minor_unit` records ISO decimals | All seeded currencies use 2 decimals. 3-decimal currencies (KWD, BHD) would need numeric(14,3); risk accepted for this market |
| D13 | When keys are declared | PKs and FKs are declared with the columns in M4; M6 adds unique, check and exclusion constraints, triggers and indexes | The lint (RG2) rejects reference columns without an FK, so declaring FKs in M6 would leave M4/M5 red. The FK design was already fixed in M3 |
| D14 | Lint heuristics refined | Money pairing accepts `<prefix>_currency_code` (ctc_amount + ctc_currency_code); `*_pct` columns are not money; `postal_code` carries `nofk:` | False positives found while building M4; the lint self-test still proves each rule fires |
| D15 | Partition key on FK children | Children of `job.application` carry `candidate_profile_id` (NOT NULL) | It is the second half of the composite FK. It also lets M18 RLS give candidates their own interviews, offers and history without a join |
| D16 | Compliance file numbering | `docs/02_compliance_table.md` (Milestone Plan name); the environment doc moved to `docs/04_environment.md` | Matches the core-gate checklist |
| D17 | Integration-boundary tables | Table comment tag `[integration-write]`: only `talentra_integration` writes; `talentra_app` reads. First use: `gig.gig_earning_reference` | Earnings are owned by the fulfilment system (docket Section 6); the app must not alter them. Applied centrally by `apply_table_standards` |
| D18 | Audit write path | `audit.log_event()` (SECURITY DEFINER) takes the actor from `app.current_user_id`, never from a parameter. Role, block, credential and consent changes are audited by triggers | Callers cannot forge the actor; sensitive changes cannot skip the trail |
| D19 | Encryption keys | Sensitive identifiers use pgcrypto with a key supplied per session (`SET app.encryption_key`), held in the application's secret store, never in the database. HMAC-SHA256 hash for duplicate detection | Docket RG6 and Section 6: no raw identifiers in clear. Key rotation re-encrypts through `org.add_identifier` (M22) |
| D20 | Login identity | Active `app_user` needs a login email or phone (`ck_app_user_login_identifier`); system actors and pending accounts are exempt | Every human actor in the audit trail is identifiable |
| D21 | Phase 2 build mode | One agent built all three Phase 2 modules on `main` (one commit), not three member branches. Module docs were drafted from DDL comments with `tools/draft_design_docs.py`, then reviewed | Time box. The m05 comparison proves the docs equal the catalog for every phase |
| D22 | API-only tables | Table comment tag `[api-write]`: the application role can only SELECT; writes go through SECURITY DEFINER functions. Used for wallet, wallet ledger, credit consumption, download history (`billing.post_ledger_entry`, `billing.record_profile_download`) and sessions/attempts/revocations (`app.start_session` ...) | Locking and invariants (device limit, non-negative balance, ledger = balance) live in one place and cannot be bypassed by the app |
| D23 | Device limit mechanism (B45) | Row lock on the user's active seat (`SELECT ... FOR UPDATE`) inside `app.start_session`; active = `ended_at IS NULL AND expires_at > now()`; rejection is returned, not raised, so the audit row commits | Proven by `tests/concurrency/m14_device_limit.ps1`: 20 parallel logins, limit 3 → 3 sessions, 17 audited rejections |
| D24 | Reversal FK name | `reverses_wallet_ledger_entry_id` (the Milestone Plan said `reverses_entry_id`) | RG1: FK = [role_]<referenced table>_id; `tools/design_docs.py` enforces it |
| D25 | Payment references | Gateway order/refund ids are stored as opaque tokens (`*_token`, Sensitive); no card or bank data anywhere | RG6 and docket Section 6 |
| D26 | Privilege enforcement (docket Section 3) | Row-Level Security on job_requirement, candidate_profile, candidate_contact and application, keyed on `app.current_user_id`, with SECURITY DEFINER helper functions (`app.actor_organisation_ids`, `app.candidate_visible_to_actor` ...). Non-row privileges use grants (`[api-write]`, append-only revokes) | Enforced for every client of the database, not only the UI. The application connects as a member of `talentra_app`, never as the table owner (owners and superusers bypass RLS) |
| D27 | Notification delivery partitioning (B57) | Monthly RANGE partitions on `queued_at`, created ahead by `notif.ensure_delivery_partitions`, plus a default partition; retention by DETACH/DROP. Provider ids are deduplicated in an unpartitioned receipt table | A unique key on a partitioned table must include the partition key, so a global provider-id key cannot live on the delivery table |
| D28 | Warehouse model | SCD2 for candidate and job dimensions, SCD1 for organisation; one `fact_application` for both pipelines; `dw.refresh_marts()` is idempotent. KPIs assumed (Section 8 not issued): funnel conversion, time to hire, volume by category | Single view of the hiring pipeline (docket Section 1); history is reported as it was at apply time |
| D29 | Warehouse privacy | Dimensions copy no names or contact details; natural keys only (`nofk`) | The warehouse can be widely read; Personal data stays in the RLS-protected operational schema |
| D30 | Seed generator (M19) | Server-side SQL (`seed/NN_*.sql`) with a deterministic hash random `seed.h(n, salt)`, not Python/Faker + COPY as planned. Name pools per locale (en, hi, ta, ar, zh) are in `seed/00_prep.sql`; volumes are psql variables set by `run.ps1 seed -Scale rehearsal|laptop` | Generating 35M+ rows inside the server avoids writing and re-reading ~10 GB of CSV; the same parameters always give the same dataset, so runs are reproducible for M21. Faker is installed but unused |
| D31 | Bulk-load integrity (M19) - **deviation** | Seed files run with `session_replication_role = replica`, which skips FK checks and user triggers during the load. CHECK, NOT NULL, UNIQUE and EXCLUDE constraints still apply. Everything skipped is re-proved afterwards by `seed/90_validate.sql` (every one of the 817 FKs scanned for orphans, legal transition chains, balances, seat/device limits, consultant/block/interviewer rules). The milestone plan said "disable no triggers" | Row-by-row FK and trigger checks made a 5M-application load impractical on a laptop. Application history is loaded directly (applications carry the final status), which was one of the two options the plan allowed. The gig overlap rule (B35) was additionally exercised live: 300 conflicting bookings attempted with constraints active, 300 rejected |
| D32 | Seed placement | Database `talentra_seed` in tablespace `talentra_data` (`D:\talentra_pg`); `pg_wal` moved to `D:\talentra_pg_wal` via a junction; server tuned per `docs/04_environment.md` (shared_buffers 4GB, pg_stat_statements) | C: has ~19 GB free. Full scale is 11 GB of data plus up to ~8 GB of WAL |
| D8 | Docket Sections 8 (KPIs), 10 (performance method, RTO) and 12 | Referenced but not issued | Request them from the organisers before M15-M23; assumptions recorded where needed |
