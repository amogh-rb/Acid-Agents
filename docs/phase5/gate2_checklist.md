# Gate 2 checklist (M23, B80-B82)

Gate 2 closes Phase 5. The phases before it were Phases 1-3 (core gate, tag `core-v1`) and Phase 4 (`phase4`).

Every row below points to evidence in the repository. The reviewer-signature column is left for the team; the AI build agent does not sign it.

## Checks
| # | Check | Evidence | Result |
|---|---|---|---|
| 1 | Fresh build: `run.ps1 up` applies all 19 DDL files with no errors | `docs/evidence/test_20261016_1248.txt` (line 2) | PASS |
| 2 | Full suite: `run.ps1 test` covers the lint and the M1-M23 tests: constraints, access, concurrency and docs | `docs/evidence/test_20261016_1248.txt` | PASS (28/28 files) |
| 3 | Dictionary and ERDs regenerated; the design docs equal the catalog both ways | m05 in the suite; `dictionary/*.csv`; `docs/erd/phase*` | PASS |
| 4 | Seed at laptop scale (B60-B64): 1M profiles, 100K jobs, 5M applications, multilingual names, 2-3% near-duplicates, funnel 30/12/4/3 | `docs/evidence/seed_laptop_20261016.txt`; 33/33 validation checks | PASS |
| 5 | Query set and validation report (B65-B69) | `docs/phase5/m20_queries.md`; `perf/results/baseline_laptop.csv`; `perf/plans/` | PASS |
| 6 | Performance: p50/p95/p99, one index per module justified, partitioning note, extrapolation naming the first query to degrade (B70-B74) | `docs/phase5/m21_performance.md`; `perf/results/*.csv` | PASS. First to degrade: Q05 candidate name substring |
| 7 | Security: PII notes, threat model, access and audit tests, RLS performance (B75-B79) | `docs/phase5/m22_security.md`; `tests/access/m18_access.sql`, `m22_privacy.sql`; `perf/results/rls_overhead.csv` | PASS (open items listed in the note) |
| 8 | Backup and restore against the assumed RTO (B80) | `docs/evidence/backup_restore_20261016_1236.txt` | PASS. Restore plus ANALYZE took 9.5 min, against an assumed RTO of 60 min (D38) |
| 9 | Security design note (B81) | `docs/phase5/m22_security.md` | Done |
| 10 | Status board: every milestone is Defined and Tested | `docs/milestones.md`; checked by `tests/docs/m23_gate2.ps1` | PASS. Verified ticks are open (row 13) |
| 11 | Compliance table and gap register are current | `docs/02_compliance_table.md`, `docs/11_coverage_gap_register.md` | Current as of M22 |
| 12 | Release | `git tag gate2` | Done with this commit |
| 13 | Human review | Reviewer sign-offs for Phases 1-5 | **OPEN.** The AI pre-review covered Phase 1 only |

## Backup and restore (B80)
**Command:** `tools/backup_restore.ps1 -Database talentra_seed -Jobs 6 -RtoMinutes 60`

**Steps and timings:**

| Step | Time | Notes |
|---|---|---|
| `pg_dump -Fd -j 6 -Z 1` to `D:\talentra_backup` | 0.6 min | 11 GB source database, 1.26 GB on disk |
| `pg_restore -j 6` into a fresh database on tablespace `talentra_data` | 8.6 min | |
| `ANALYZE` | 0.9 min | |
| **Recovery time (restore + ANALYZE)** | **9.5 min** | Assumed RTO 60 min (D38) |

**Verification:**
- Exact `count(*)` on all 203 tables: 53.7M rows, 0 mismatches. Examples: 1,000,000 profiles; 5,000,000 applications; 9,874,702 status-history rows.
- 0 invalid indexes.
- 61 of 61 RLS policies restored.

**Not covered by this drill:**
- **Point-in-time recovery.** A logical dump restores to the moment of the dump. Production needs base backups plus WAL archiving (`archive_mode`, pgBackRest or WAL-G) to reach an RPO of minutes.
- **The tablespace layout.** The restore recreates `talentra_data` objects in the target database's default tablespace, so the tablespace must exist on the target server.
- **Backup encryption** (threat T4). The dump is not encrypted at rest. Production should encrypt the backup volume or use the backup tool's encryption.

**Extrapolation:**
- Restore time is dominated by index builds and grows roughly linearly with data size.
- 10× scale (about 110 GB) would take about 1.5 h with 6 jobs. That exceeds a 60-minute RTO.
- At that size, recovery must use physical backups (base backup plus WAL replay, or a standby promotion), not `pg_restore`.

## What can be shown to the panel
- The whole schema (203 tables) is built from scratch in one command, and the suite proves every docket rule with named constraint failures.
- 1M candidates, 100K jobs and 5M applications are loaded and validated: zero orphan rows across 817 foreign keys, and legal pipeline histories.
- Measured query latencies, the index each module needs (20×-2,290× speed-ups), and a measured projection of what degrades first at 10M and 100M.
- **Privileges enforced in the database:**
  - A recruiter cannot see a candidate who blocked their company, even through skills or address tables.
  - Erasure on request is audited.
  - Retention windows are applied by an audited job.
  - RLS was made fast at scale: the skill search went from 80 s to 3.4 ms.
- **A 9.5-minute verified restore of the full dataset.**

## Sign-off
| Role | Name | Time (IST) | Signature |
|---|---|---|---|
| Build (AI agent; not an independent review) | Claude | 2026-10-16 | Gate 2 checks 1-12 run and recorded above |
| Reviewer (C) | | | |
| Member A | | | |
| Member B | | | |
