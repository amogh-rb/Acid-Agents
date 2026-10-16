# M22: security design note, PII handling and threat model (B75-B79)

**Scope:** the PostgreSQL database of Talentra. That covers its roles, data classes, access rules, retention and audit. The application tier, network and hosting are out of scope; they appear only as assumptions about how the application connects.

**Evidence:**
- **Tests:** `tests/access/m22_privacy.sql` (anonymisation, retention, RLS on the profile's Personal tables, candidate search), `tests/access/m18_access.sql` (row-level security on jobs, profiles, contacts, applications) and the m14 and m10 tests (licences, ledger, audit).
- **Performance of the access layer:** `perf/results/rls_overhead.csv`, section 4.

## 1. Data classification and PII inventory (B75)
Every column carries one of four classes in its comment. The lint enforces this (RG6), and the dictionary exports it (`dictionary/columns.csv`, column `sensitive_class`).

| Class | Columns | Handling |
|---|---|---|
| Public | 502 | Lookups, published job content, labels |
| Internal | 1,438 | Keys, statuses, timestamps, operational data |
| **Personal** | **126** | Identifies or describes a person. Protected by RLS, anonymised on request, never copied to the warehouse |
| **Sensitive** | **11** | Must never be readable even by an authorised viewer. Stored only as a hash, token, ciphertext or last 4 characters (the lint rejects other storage) |

**Sensitive columns and how each is stored:**

| Column | Storage | Why |
|---|---|---|
| `admin.user_credential.password_hash` | argon2id or bcrypt PHC string, never the password (`ck_user_credential_password_hash_format`, `ck_user_credential_hash_matches_algorithm`) | Credentials |
| `lic.login_session.session_token_hash`, `lic.registered_device.device_fingerprint_hash` | SHA-256 (32 bytes, checked) | A stolen table cannot be replayed as sessions |
| `org.organisation_identifier.value_encrypted` / `value_hash` / `value_last4` | pgcrypto `pgp_sym_encrypt` with the key supplied by the caller and held outside the database; HMAC for uniqueness; last 4 for display (D19) | Tax and registration IDs must be recoverable for verification, but never stored in clear |
| `profile.candidate_identity_document.verification_token` / `identifier_hash` / `identifier_last4` | Verification-service token plus HMAC plus last 4. The ID number itself is never stored | Aadhaar and other national IDs: minimum necessary |
| `billing.payment_order.gateway_order_token`, `billing.refund.gateway_refund_token` | Opaque gateway tokens (D25); no card data ever enters the database | Payment card industry scope stays at the gateway |

**Where the Personal data is:**
- **Candidate profile and its 14 child tables:** name, date of birth, gender, salary, address, contacts, education, experience, skills, languages, certifications, projects, links, resumes, assessments, courses.
- **Login identity:** `admin.app_user` login email and phone.
- **Application tables:** cover note, screening answers, interview feedback, offer CTC.
- **Gig worker profile, availability and earnings.**
- **Support tickets and community posts:** free text.
- **Masked IPs** in the audit, consent and login-attempt tables. They are stored masked (`/24`, `x` in the last octet).

**Deliberate decision on contact details (recorded in the compliance table, RG6):**
- The Delivery Plan proposed encrypting contact details with pgcrypto. They are Personal, not Sensitive, so they are stored in clear and protected by RLS and anonymisation instead.
- The reason is that the product must search, de-duplicate and verify them. The near-duplicate check (Q04) and the email lookup (Q03) need an index on the value. Encrypting them would require deterministic encryption, which leaks equality anyway, or a blind index.
- This is a reviewed trade-off, not an omission.

**Warehouse:** the `dw` dimensions copy no names, contacts or identifiers (D29). Analysts read the warehouse through `talentra_readonly`, so most Personal data never leaves the RLS-protected schema.

## 2. Access model (B76)
| Layer | Mechanism |
|---|---|
| **Connection roles** | The application connects as a login role in `talentra_app`, BI uses `talentra_readonly`, and integrations use `talentra_integration`. None owns tables, and none is a superuser, so RLS always applies to them |
| **Actor** | Every transaction sets `app.current_user_id`. `created_by` and `updated_by` default to it, and an insert without an actor fails, so there is no anonymous write |
| **Grants** | These are derived from the table comment: append-only tables get no UPDATE or DELETE, `[api-write]` tables are written only through SECURITY DEFINER functions, and `[integration-write]` tables are written only by the integration role |
| **Row-level security** | Policies (actor facts evaluated once per statement, D36) cover: jobs (the recruiter's own organisation, consultant-open, published for others); candidate profile (the candidate, admins, and the hiring side minus blocked and hidden); contacts, applications, and since M22 every Personal child table of the profile. Identity documents are visible only to the candidate and admins |
| **Business-rule triggers** | Consultants act only on consultant-open jobs (B46); an interviewer must belong to the job's organisation (F3); outreach never reaches a candidate who blocked the sender; device and seat limits are enforced under row locks (B37-B39) |
| **SECURITY DEFINER APIs** | Login and session management, ledger postings, profile downloads, identifier encryption, anonymisation, candidate search. Each validates the actor itself and pins `search_path` |

## 3. Retention and deletion (B77)
| Data | Rule (from the table comment) | Mechanism |
|---|---|---|
| Candidate (on request) | Anonymised 30 days after the request (`deleted_at` set) | `admin.run_retention()` calls `admin.anonymise_user()`. The user can also call it directly for immediate erasure |
| Candidate (inactive) | Anonymised after 36 months without a login | Same job. `idx_app_user_last_login_at` keeps the scan cheap |
| Login sessions | 90 days after they end | Hard delete; sessions with a revocation row wait for it |
| Session revocations, login attempts | 1 year | Delete through the append-only guard's retention exception (D35) |
| Notifications | 180 days; deliveries cascade | Old delivery months are detached and dropped as partitions |
| Support tickets | 2 years after resolution | Messages cascade |
| Error log / audit trail | 90 days / 7 years | Delete through the guard exception |

**What anonymisation does (`admin.anonymise_user`):**
- It blanks every Personal column of the profile.
- It deletes contacts, addresses, identity documents, links, education, experience, skills, languages, certifications, projects, preferences, courses and saved searches.
- It blanks resume content but keeps the rows, because applications reference them, and it clears application cover notes.
- It ends sessions, deletes the credential, and frees the login email and phone.
- It records `user_anonymised` in the audit trail with the reason.
- **Kept:** application and status-history rows, ledgers and audit rows. They no longer identify the person, and the employer's pipeline statistics, the money trail and the audit obligations depend on them.

**Append-only and retention (D35):**
- The guard `audit.forbid_update_delete` lets a DELETE through only when `app.retention_purge = 'on'`.
- Only `admin.run_retention()` sets it, transaction-locally, and it is not executable by the application role.
- UPDATE and TRUNCATE stay forbidden.
- The application role has no DELETE grant on append-only tables, so setting the flag gives it nothing. This is tested.

**Scheduling:** run daily as the database owner, through Windows Task Scheduler (`tools/run_retention.ps1`) or pg_cron on Linux:

    SET app.current_user_id = '1'; SELECT admin.run_retention();

Each run is audited (`retention_purged`) with the counts per table.

## 4. RLS performance on candidate search (B79, the Delivery Plan's key risk)
See the measured results below (`perf/results/rls_overhead.csv`, laptop scale, recruiter of a seeded company, 20 runs).

**Method:**
- `perf/rls_overhead.ps1` runs the same query as the table owner (RLS bypassed) and as a recruiter through `talentra_app` (RLS applied).
- Data is `talentra_seed` at 1M profiles; each query has 2 warm-up runs then 20 measured runs.
- R5 is capped at 3 runs.

**Results (final policies):**

| Query | Owner p50 | Recruiter (RLS) p50 | First attempt (M18 policies) |
|---|---|---|---|
| R1 candidate by exact email | 0.03 ms | 0.67 ms | |
| R2 one profile with skills and education | 0.05 ms | 0.80 ms | |
| R3 name contains 'Iyer', top 50 (plain `ILIKE` on the table) | 2.2 ms | 49 ms | 3.3 s |
| R4 candidates with a skill, open to work, top 50 | 0.23 ms | 3.4 ms | 80 s |
| R5 count of all name matches (plain `ILIKE`, unbounded) | 43 ms | **91 s** | > 9 min (cancelled) |
| R6 name search through `app.search_candidates_by_name` | n/a | **5.2 ms** | |

**What was wrong and how it was fixed (D36).** Three separate problems appeared one after another at 1M rows. None of them shows at test scale.

1. **Actor facts were evaluated per row.**
   - Policies called `app.actor_is_platform_admin()` and similar helpers directly, so they ran once for every row scanned.
   - Fix: wrap each one as `(SELECT app.actor_…())`. PostgreSQL then computes it once per statement as an InitPlan.
2. **The block check was probed per candidate.**
   - The visibility function searched `block_list` for every candidate. That cost 0.15 ms per call when an index matched and 4.7 ms when it fell back to a scan.
   - Fix: `app.actor_blocking_user_ids()` computes once per statement the few candidates who blocked this actor or their organisations, and each row is tested against that array.
   - The function became PL/pgSQL, so only the branch that is taken runs. A SQL function initialised all three branches on every call, including the 32-partition application lookup.
3. **Child-table policies were planned as a hashed subplan.**
   - The form `EXISTS (SELECT 1 FROM candidate_profile WHERE id = candidate_profile_id)` was executed by building a hash of every visible profile. That meant running the profile policy on 880K rows (80 s) to return 50 skills.
   - Fix: `app.candidate_profile_visible(id, …)` checks one profile by primary key per child row.

**What still costs, and the rule for the application:**
- **Unbounded pattern scans under RLS are slow (R5).** `ILIKE` is not leakproof, so PostgreSQL must apply the policy before the pattern and cannot use the trigram index. A count over every profile therefore checks visibility 1M times.
- **The application must not run R5.** It calls `app.search_candidates_by_name` (R6, 5.2 ms). That function uses the trigram index first, applies the same visibility rule to the matches only, caps the result at 200 rows and needs at least 3 characters.
- **Approximate result counts** come from the search service or `EXPLAIN` estimates, never from `count(*)` under RLS.
- **Safety net:** the application's login role gets `ALTER ROLE <login> SET statement_timeout = '5s'`, so an accidental unbounded query is cancelled instead of tying up a backend. `talentra_app` is a NOLOGIN group role, and role settings do not inherit, so this goes on the login role.
- **Remaining overhead:** RLS adds about 15-25× to point lookups (0.03 → 0.7 ms) and 15× to bounded searches. That is acceptable: every candidate-side interaction stays below 50 ms at 1M profiles.

## 5. Threat model (B78)
STRIDE over the database boundary. "Residual" means what is still possible after the controls listed.

| # | Threat | Asset | Control in the database | Test / evidence | Residual risk |
|---|---|---|---|---|---|
| T1 | A recruiter reads candidates who blocked their company, or hidden profiles (**information disclosure**) | Profile and Personal children | RLS with the block list and visibility preference; children inherit the profile rule through `app.candidate_profile_visible` (one PK lookup per row) | m18_access, m22_privacy | A search that bypasses the API function falls back to RLS: still correct, but slow (section 4) |
| T2 | A recruiter reads or edits another company's jobs or applications (**elevation of privilege**) | Jobs, applications | RLS on `job_requirement` and `application` keyed on the recruiter mapping in force today | m18_access | Mapping changes take effect immediately; no caching |
| T3 | The application is compromised and runs arbitrary SQL as `talentra_app` (**tampering**) | Audit trail, ledger, history | No UPDATE or DELETE grants on append-only tables, plus the guard trigger; ledger writes only through `post_ledger_entry`; RLS still filters reads | m01, m14_billing, m18_access, m22 (purge flag useless to the app) | The attacker can still read whatever a platform admin could, if it can set `app.current_user_id` to an admin id. **The actor GUC is set by the application tier and is not authenticated by the database.** Mitigation: a connection pool per tier; future work: signed or verified actor sessions (`SECURITY DEFINER` login that sets the actor from a session token) |
| T4 | Theft of a backup or a disk (**information disclosure**) | All data | Sensitive values are hashed, encrypted or tokenised; the organisation-identifier key is not in the database | Lint RG6 | Personal data such as names and contacts is in clear in the backup. Mitigation: encrypted backups (M23) and disk encryption (BitLocker on D:) |
| T5 | A credential or session replayed from a leaked table (**spoofing**) | Logins | Only hashes of passwords, session tokens and device fingerprints are stored | m14_lic | Legacy bcrypt hashes are marked `bcrypt_legacy` (rehash at next login); `must_change_password` forces a change |
| T6 | Licence sharing beyond the device limit (**repudiation / abuse**) | Licence revenue | Seat and session limits under row locks; rejections audited | m14 concurrency: 20 parallel logins, 3 sessions, 17 audited rejections | None at the database level |
| T7 | A double charge or replayed payment webhook (**tampering**) | Wallet, payments | Idempotency keys; unique gateway event ids; refund cap trigger; balance ≥ 0 | m14_billing | Reconciliation with the gateway is outside the database |
| T8 | Erasure not honoured, or data kept past its window (**compliance**) | Personal data | `anonymise_user`, `run_retention`, audited | m22_privacy | The job must be scheduled. The audit trail shows when it last ran (`retention_purged`) |
| T9 | An admin silently reads or edits data (**repudiation**) | Everything | Audit triggers on role grants, blocks, credentials and consent; profile downloads audited by `billing.record_profile_download`; logins, device-limit rejections, revocations, anonymisation and retention runs audited; `created_by` and `updated_by` on every row | m10_admin, m14, m22 | Plain SELECTs by admins are not audited. The `identifier_viewed` action exists but no function decrypts identifiers yet: decryption must go through a future audited reveal function (open item) |
| T10 | SQL injection through a SECURITY DEFINER function (**elevation**) | Everything | Every definer function pins `search_path`, uses parameters or `format(%I, %L)`, and escapes LIKE input (`search_candidates_by_name`) | Code review; m22 (`%%%` returns nothing) | New definer functions must follow the same rule (checklist item) |
| T11 | Denial of service through expensive queries (**DoS**) | Availability | Candidate name search goes through `app.search_candidates_by_name` (trigram index, ≥ 3 characters, ≤ 200 rows); policies evaluate actor facts once per statement; employer queries index-backed (M21) | Section 4 (R1-R6), M21 | An unbounded `ILIKE` count under RLS takes 91 s (R5). Mitigation: `statement_timeout = 5s` on the application's login role (section 4) |

## 6. Open items
- **Verified actor sessions (T3):** replace "the application sets `app.current_user_id`" with a SECURITY DEFINER function that sets it from a session token hash. Until then, the database trusts the application tier for identity.
- **Remaining Personal tables outside RLS** (grants only): application answers, interview feedback, offers, gig worker data, support tickets, referrals. Apply the same `EXISTS`-on-parent pattern when those modules expose direct table access.
- **Gig workers:** anonymising a gig worker profile is not part of `anonymise_user` yet; the candidate side is complete.
- **Admin reads:** auditing every admin SELECT needs `pgaudit`.
- **Identifier reveal:** add `org.reveal_identifier(id, key)` that decrypts and writes `identifier_viewed`; until then decryption is an ad-hoc owner operation.
