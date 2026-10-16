# M21: performance baseline, index justification, partitioning and extrapolation (B70-B74)

## Test bed
- **Machine:** Intel i7-1255U (12 threads), 31.6 GB RAM, WD SN740 NVMe SSD, Windows 11.
- **Database:** PostgreSQL 18.4 with the tuned settings in `docs/04_environment.md`:
  - memory: shared_buffers 4GB, effective_cache_size 16GB, work_mem 32MB;
  - planner: random_page_cost 1.1;
  - statistics: pg_stat_statements on.
- **Data:** `talentra_seed` (laptop scale: 1M profiles, 100K jobs, 5M applications, 11 GB) and `talentra_seed_small` (the same generator at 1%).
- **Placement:** both databases are on tablespace `talentra_data` (D:); WAL is also on D:.
- **Method:**
  - execution time comes from `EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)`, measured server-side;
  - the query set runs 3 warm-up runs then 30 measured runs; the index experiments run 2 warm-up and 20 measured;
  - DML is rolled back.
- **Cache state:** all numbers are hot-cache, because the 11 GB database fits in RAM.

## 1. Baseline (B70)
`perf/results/baseline_laptop.csv` (p50/p95/p99 for Q01-Q13). The table and plans are in `docs/phase5/m20_queries.md`.

| | p50 | p95 | p99 |
|---|---|---|---|
| Point lookups (Q01, Q03, Q04, Q06) | 0.04-0.10 ms | ≤ 0.23 ms | ≤ 0.27 ms |
| Transactions (Q11 apply, Q12 login, Q13 debit) | 0.34-0.91 ms | ≤ 2.2 ms | ≤ 3.0 ms |
| Search and aggregates (Q02, Q07, Q09, Q10) | 2.8-13.9 ms | ≤ 15.6 ms | ≤ 15.8 ms |
| Slowest (Q05 name substring, Q08 company jobs with counts) | 60-62 ms | 86-133 ms | 90-135 ms |

## 2. One index per module, before and after (B71-B73)
Method (`perf/index_experiments.ps1`):
1. Drop the index and measure the query it exists for (BEFORE).
2. Recreate the index from its saved definition and ANALYZE (AFTER).
3. Measure again.

The script always restores the index. Results are in `perf/results/index_experiments.csv` and `index_experiment_notif_queue.csv`. Plans are in `perf/plans/idx_*_{before,after}.txt`.

| Module | Index | Query it serves | Before p50 | After p50 | Speed-up | Size | Build |
|---|---|---|---|---|---|---|---|
| Profile | `idx_candidate_profile_full_name_trgm` (GIN trigram) | name contains '…Subramaniam…', top 50 | 286.1 ms | 0.83 ms | 346× | 19 MB | 1.6 s |
| Jobs and applications | `idx_job_requirement_open_published` (partial) | newest open jobs for a role | 82.2 ms | 0.05 ms | 1,552× | 0.8 MB | 0.3 s |
| Administration | `idx_audit_event_actor_app_user_id` | an actor's latest audit events | 83.2 ms | 0.04 ms | 2,080× | 23 MB | 0.5 s |
| Organisation and account | `idx_recruiter_mapping_organisation_id` | a company's current recruiters | 1.03 ms | 0.02 ms | 52× | 0.3 MB | 0.1 s |
| Gig marketplace | `idx_gig_request_open` (partial) | open gigs for a skill, by start | 3.67 ms | 0.04 ms | 92× | 0.3 MB | 0.2 s |
| Licences, devices and sessions | `idx_login_session_active_user` (partial) | active sessions of a user (device-limit check) | 1.88 ms | 0.03 ms | 67× | 0.5 MB | 0.3 s |
| Sourcing | `idx_outreach_recipient_candidate_profile_id` | outreach a candidate received | 2.14 ms | 0.01 ms | 178× | 3 MB | 0.2 s |
| Subscriptions and wallet | `idx_wallet_ledger_entry_wallet_id` | a wallet's latest ledger entries | 84.7 ms | 0.04 ms | 2,290× | 26 MB | 0.6 s |
| Notifications | `idx_notification_delivery_pending` (partial, partitioned) | next 100 queued deliveries | 162.1 ms | 0.40 ms | 409× | per partition | 1.2 s |
| Analytics | `idx_fact_application_applied_dim_date_id` | last 30 days of facts by category | 357.2 ms | 17.3 ms | 21× | 41 MB | 6.8 s |

**Index that is not justified:** `notif.idx_notification_unread` (partial, unread per recipient) gave ×1.1 (0.036 → 0.032 ms).
- The existing `idx_notification_recipient_app_user_id (recipient, created_at)` already finds a user's notifications.
- The seed has about one notification per user, so filtering for unread costs nothing.
- The index would pay off only for users with hundreds of mostly read notifications.
- It is kept for now and listed as a removal candidate (D34), to be decided with production-like per-user volumes.

**Incident found and fixed during the experiment:**
- For a partitioned table, `pg_get_indexdef` returns `CREATE INDEX … ON ONLY …`. Recreating from that text built an invalid parent index with no partition indexes.
- The script now strips `ONLY` before recreating the index.
- The index was rebuilt, and the database was verified to have zero invalid indexes (`pg_index.indisvalid`) and a child index on all 30 delivery partitions.
- Lesson for operations: rebuild partitioned indexes without `ONLY`, or attach each partition index explicitly.

## 3. Partitioning note (B72)
| Table | Strategy | Rows (laptop) | Size | Status |
|---|---|---|---|---|
| `job.application` | HASH (candidate_profile_id), 32 partitions (D5) | 5.0M | 1.4 GB | Built in M6 |
| `notif.notification_delivery` | RANGE (queued_at) monthly + default (D27) | 1.5M | — | Built in M18 |
| `job.application_status_history` | none | 9.9M | 1.46 GB | Decision D33 |
| Event tables: `profile_view_event`, `candidate_activity_event`, `job_search_event`, `audit_event`, `profile_download_event`, `wallet_ledger_entry` | none | 0.5-1.0M each | 112-211 MB each | Decision D33 |

**Measured effect of D5 (hash partitioning on the candidate):**
- Candidate-side queries prune to one partition. Q06, "my applications", takes 0.05 ms and touches 23 buffers.
- Employer-side queries filter on the job, which is not the partition key, so they probe all 32 partitions:
  - Q07 (one job's pipeline) takes 13.9 ms;
  - Q08 (a company's jobs) takes 60 ms.
- Each probe is an index-only or index scan, so the fan-out costs about 32 index descents. It does not scan the tables.
- This is the accepted trade-off: the uniqueness of (candidate, job) and the candidate's view stay cheap, while the employer view pays a bounded fan-out.

**D33 (event tables):**
- Keep the event tables unpartitioned at laptop scale. No query in the set filters them by time, and each is under 250 MB.
- Partition them by monthly RANGE when a table passes about 50M rows or when retention needs whole-month drops. That happens around 10× scale for the profile and search events.
- The `notif.ensure_delivery_partitions` pattern applies unchanged.
- No FK points at these tables except into `wallet_ledger_entry` (from `credit_consumption`, the download and the profile view). The ledger is therefore partitioned last, and only after those FKs become composite with the partition key, as `application` did in D5.
- `application_status_history` should follow `application` with HASH (candidate_profile_id, 32). It already carries `candidate_profile_id` (D15), and at 100× it reaches about 1B rows.

## 4. Extrapolation to 10× and 100× (B74)
**Method:**
- The query set was measured at two scales 100× apart: 1% (`talentra_seed_small`, 10K profiles) and 100% (1M profiles).
- For each query, the growth exponent *k* in t ∝ n^k comes from the two p50 values: k = log(t₁₀₀/t₁) / log 100.
- That *k* is applied to the laptop time: t(10×) = t·10^k, t(100×) = t·100^k.
- Script: `perf/extrapolate.py`; output: `perf/results/extrapolation.csv`.

| Rank | Query | k | Now (1M) | 10× (10M profiles) | 100× (100M) | 100× p95 |
|---|---|---|---|---|---|---|
| **1** | **Q05 candidate name substring** | **1.07** | **62 ms** | **~0.74 s** | **~8.7 s** | ~18.6 s |
| 2 | Q08 company's open jobs with counts | 0.62 | 60 ms | ~0.25 s | ~1.0 s | ~1.5 s |
| 3 | Q02 job keyword search | 0.94 | 10 ms | ~88 ms | ~0.76 s | ~0.87 s |
| 4 | Q07 one job's pipeline counts | 0.51 | 14 ms | ~45 ms | ~0.15 s | ~0.17 s |
| — | Q09 skill match (top 50) | 0.10 | 3.3 ms | ~4 ms | ~5 ms | |
| — | Lookups and transactions (Q01, Q03, Q04, Q06, Q10-Q13) | ≤ 0.09 | ≤ 2.8 ms | ≤ 3 ms | ≤ 3.2 ms | |

**The first query to degrade is Q05, the candidate name substring search.**
- Its cost is linear (k ≈ 1). The trigram index finds candidate rows quickly, but the query then reads and counts every match, and the number of matches grows with the data. 25K profiles match '%Iyer%' at 1M.
- It passes an interactive budget of 500 ms at roughly 7M profiles.

**Mitigations:**
- Return a ranked top-N (`LIMIT`, `similarity()` order) instead of a full count. The trigram experiment shows 0.8 ms for a top-50.
- Require at least 3 characters plus one structured filter (city, role).
- Show approximate counts.
- At 100× scale, move free-text candidate search to a search service fed from the database.

**Next in line:**
- **Q08 and Q07** grow with the applications per job and the D5 fan-out. Fix: a maintained per-job counter, or read from `dw.agg_daily_funnel` / a job-level aggregate.
- **Q02** grows with the number of matching open jobs. Fix: a top-N with `ts_rank` on a narrower candidate set, or a RUM index that supports ordered retrieval.

**Caveats (why these are lower bounds):**
1. Both measurements are hot-cache. At 10×, the data (about 110 GB) is larger than RAM (32 GB), so scans that touch many rows (Q05, Q08, Q02) also pay SSD reads. The buffer counts in the plans (17.8K for Q05, 46.9K for Q08, at 8 KB each) show how much I/O each run would need cold.
2. Two points fit a power law exactly. They do not show curvature, for example a plan changing at some size.
3. Queries with a LIMIT and an index order (Q01, Q09) stay flat only while the plan keeps the index-ordered path. Q09's estimate without the limit is about 2.8M index entries, so the limit is load-bearing: do not remove it.
4. Concurrency was measured separately (M14: 20 parallel logins). Throughput under mixed load is not part of this baseline.
