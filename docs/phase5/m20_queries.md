# M20: query set and seed validation report (B65-B69)

**Database:** `talentra_seed` at laptop scale: 1M candidate profiles, 100K jobs, 5M applications (M19, D30-D32).
**Server:** PostgreSQL 18.4 with the tuned settings in `docs/04_environment.md` (shared_buffers 4GB, random_page_cost 1.1).
**Method:** `perf/run_queries.ps1 -Runs 30 -Warmup 3`.
- Each run is `EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)` inside `BEGIN ... ROLLBACK`, so the DML queries leave no trace.
- Times are server-side execution times, without network or client overhead.
- Parameters come from `queries/_params.sql`. They are picked from the data so each query has something to find, for example the most-applied-to job and a seeded near-duplicate.
- **Outputs:**
  - raw numbers: `perf/results/baseline_laptop.csv`;
  - plans: `perf/plans/Qnn_*_baseline_laptop.txt`.

## Query set
| Query | Purpose (module) | Kind | Rows | p50 ms | p95 ms | p99 ms | Access path |
|---|---|---|---|---|---|---|---|
| Q01 | Job search by role, newest first (Jobs) | lookup | 20 | 0.10 | 0.23 | 0.27 | partial index `idx_job_requirement_open_published` read in order; no sort |
| Q02 | Job search by keyword (Jobs) | performance | 20 | 10.2 | 11.7 | 14.1 | BitmapAnd of full-text `idx_job_requirement_search_document` and the open/published partial index; top-20 sort of ~5K matches |
| Q03 | Candidate by exact email (Profile) | lookup | 1 | 0.04 | 0.08 | 0.10 | `uq_candidate_contact_email` |
| Q04 | Duplicate profiles sharing a phone (Profile, data quality) | lookup | 2 | 0.06 | 0.09 | 0.15 | `idx_candidate_contact_phone` |
| Q05 | Candidate name substring `%Iyer%` (Profile) | performance | 1 (count of 25K) | 62.5 | 132.5 | 135.3 | trigram GIN `idx_candidate_profile_full_name_trgm`, then 25K heap rows |
| Q06 | A candidate's applications (Applications) | functional | 5 | 0.05 | 0.10 | 0.21 | partition pruning to one hash partition (`application_h15`) |
| Q07 | Pipeline counts of the hottest job (Applications) | functional | 7 | 13.9 | 15.6 | 15.8 | index-only scans over all 32 partitions (50K rows; the job is not the partition key) |
| Q08 | A company's open jobs with application counts (Jobs + Applications) | functional | 9 | 60.0 | 85.6 | 90.3 | job index, then 9 × 32 partition index probes (50K applications) |
| Q09 | Candidates holding every mandatory skill of a job (matching) | performance | 50 | 3.3 | 4.2 | 4.9 | walks `uq_candidate_skill (candidate, skill)` in candidate order until 50 matches |
| Q10 | Monthly funnel by category (Analytics) | analytics | 134 | 2.8 | 4.3 | 4.3 | `dw.agg_daily_funnel` (3.8K rows) instead of 5M facts |
| Q11 | Apply to a job (Applications) | transactional | insert | 0.43 | 2.22 | 3.04 | transition and history triggers, RLS bypassed as owner |
| Q12 | Start a session (Licences) | transactional | 1 | 0.91 | 2.12 | 2.13 | `app.start_session`: seat row lock, device-limit count, audit on rejection |
| Q13 | Post a wallet debit (Billing) | transactional | 1 | 0.34 | 1.07 | 1.23 | `billing.post_ledger_entry`: wallet row lock, idempotency key |

**Expected shape:** every query returns the columns and row count its purpose implies:
- top-20 lists return 20 rows;
- exact lookups return 1 row;
- the duplicate check finds the seeded twin;
- the funnel returns one row per month and category;
- DML returns one inserted row or posted entry.

Any failing query is reported as `FAIL` by the runner and recorded with `error=failed` in the CSV. There are none.

## Observations carried into M21
- **Q05 and Q08 are the slowest reads.** Both scale with the number of matching rows, not with the index lookup.
  - Q05 reads 25K matching profiles (17.8K buffers) to count them.
  - Q08 visits 50K applications of one company's jobs (46.9K buffers).
- **Partitioning cost.** Q07 and Q08 filter on `job_requirement_id`, which is not the partition key, so every one of the 32 partitions is probed. Q06 filters on the candidate and touches one partition. This is the D5 trade-off: candidate-side queries prune, employer-side queries fan out.
- **Q09 is fast only because of `LIMIT 50`.** Its cost estimate (134K) shows that without the limit it would scan all 2.8M candidate-skill rows. At 10× scale it is the most likely query to degrade first; M21 measures it with a `(skill_id, candidate_profile_id)` index.
- **Transactions stay low:** apply, login and debit are each under 1 ms at p50 and about 3 ms at p99, with their triggers and row locks active.

## Seed validation report against docket Section 5
`seed/90_validate.sql` was run on the same database (evidence: `docs/evidence/seed_laptop_20261016.txt`). Result: **33 checks, 0 failed.**

| Area | What was checked | Result |
|---|---|---|
| Volumes | profiles, jobs, applications, organisations equal the requested scale | 1,000,000 / 100,000 / 5,000,000 / 10,000 |
| Referential integrity | every one of the 817 FKs scanned for orphan rows (the bulk load skipped FK triggers, D31) | 0 orphans |
| Pipeline (RG2) | every history row is a legal transition; one initial row per application; final status = last history row; no applications to draft jobs | 0 violations each |
| Funnel distribution | share that reached each stage, ±1 point | shortlisted 30.00%, interviewed 12.01%, offered 4.00%, joined 2.99% |
| Money (RG10) | wallet balance = sum of ledger; running balance = cumulative sum; every download has a debit; no over-refund | 0 violations each |
| Licences (RG9) | seats ≤ max users; active sessions ≤ devices allowed | 0 violations each |
| Access (Section 3) | sourcing only on consultant-open jobs; no outreach to a candidate who blocked the sender; interviewers belong to the job's company; no hierarchy cycles | 0 violations each |
| Standards (RG3, RG5, RG6, RG7) | no zero/negative salary sentinels; undisclosed salaries are NULL (629,481); emails lowercase; phones E.164 with country; org identifiers encrypted; native scripts present (Devanagari 242K, Tamil 145K, Arabic 77K, Han 116K) | pass |
| Data quality | near-duplicates detectable by shared phone | 2.68% (target 2-3%) |
| Partitioning | max/min rows across the 32 application partitions | 1.026 |
| Gig (B35) | conflicting bookings attempted live, with constraints on | 300 attempted, 300 rejected |
| Warehouse | fact rows = job + gig applications | 5,094,825 |
