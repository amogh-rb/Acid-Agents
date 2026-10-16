# Milestone status board

A milestone is done only when it is **Defined** (deliverable committed), **Verified** (someone other than the author ticked the checklist; initials and time), and **Tested** (`.\run.ps1 gate Mnn` prints PASS on a fresh database).
- Times are IST.
- Update this file in the same commit that closes the milestone.

| M | Backlogs | Scope | Owner | Defined | Verified (by, time) | Tested (gate, time) | Notes |
|---|---|---|---|---|---|---|---|
| M1 | B1-B3 | Provider, module list, build base | All | ✅ 12:25 | AI pre-review 13:07 (C to confirm) | ✅ gate M1 12:17 (72 checks) | Evidence: `docs/evidence/gate_M01_*.txt` |
| M2 | B4-B7 | Entities: Master data, Profile, Jobs | A, B | ✅ 12:24 | AI pre-review 13:07 (C to confirm) | ✅ gate M2 12:27 | 96 entities (2 stubs, 50 ref of which 3 built in M1, 24 profile, 20 job); `docs/phase1/entities.md` |
| M3 | B8-B11 | Relationships + ERD + stubs | A, B | ✅ 12:26 | AI pre-review 13:07 (C to confirm) | ✅ gate M3 12:27 (5/5 files) | 153 FKs; `docs/phase1/relationships.md`, `docs/erd/phase1.mmd`, `ddl/10_ref.sql` (status lookups), `ddl/15_stubs.sql` |
| M4 | B12-B15 | Columns + comments + lookup seed | A, B | ✅ 12:42 | AI pre-review 13:07 (C to confirm) | ✅ gate M4 12:46 | `ddl/10_ref.sql`, `20_profile.sql`, `30_jobs.sql`: 96 tables, PKs + FKs declared now (D13), 0 lint violations |
| M5 | B16-B19 | Dictionary + generated ERD + design note | C | ✅ 12:45 | AI pre-review 13:07 (C to confirm) | ✅ gate M5 12:46 (7/7 files) | `dictionary/*.csv` (994 columns), `docs/erd/phase1_generated.mmd`, `docs/phase1/design.md`; design vs catalog proven by test |
| M6 | B20-B23 | Keys, constraints, transition trigger, Phase 1 sign-off | A, B | ✅ 12:58 | AI pre-review 13:07; C signs `docs/phase1/signoff.md` | ✅ gate M6 12:58 (8/8 files, 43 M6 checks) | `job.application` hash-partitioned (D5); compliance table `docs/02_compliance_table.md`; tag `phase1` |
| M7 | B24-B26 | Entities: Admin / Org / Gig | A / B / C | ✅ 13:44 | ☐ | ✅ gate M10 13:47 | `docs/phase2/{admin,org,gig}_entities.md` (44 entities) |
| M8 | B27-B29 | Relationships: Admin / Org / Gig | A / B / C | ✅ 13:44 | ☐ | ✅ gate M10 13:47 | `docs/phase2/*_relationships.md` (73 FKs), `docs/erd/phase2_*.mmd` |
| M9 | B30-B32 | Columns: Admin / Org / Gig | A / B / C | ✅ 13:40 | ☐ | ✅ gate M10 13:47 | `ddl/40_admin.sql`, `45_org.sql`, `50_gig.sql`; dictionary 1,433 columns |
| M10 | B33-B35 | Keys and constraints + tests: Admin / Org / Gig | A / B / C | ✅ 13:47 | ☐ | ✅ gate M10 13:47 (13/13 files; m10: 27 + 16 + 22 checks) | Tag `phase2`. Built by one agent on main (D21) |
| M11 | B36-B38 | Entities: Licences / Sourcing / Subscriptions | A / B / C | ✅ 14:03 | ☐ | ✅ gate M14 14:07 | `docs/phase3/{lic,src,billing}_entities.md` (40 entities) |
| M12 | B39-B41 | Relationships | A / B / C | ✅ 14:03 | ☐ | ✅ gate M14 14:07 | `docs/phase3/*_relationships.md` (75 FKs), `docs/erd/phase3_*.mmd` |
| M13 | B42-B44 | Columns | A / B / C | ✅ 14:00 | ☐ | ✅ gate M14 14:07 | `ddl/60_lic.sql`, `65_src.sql`, `70_billing.sql`; dictionary 1,827 columns |
| M14 | B45-B47 | Keys and constraints + tests (incl. 20-login concurrency) | A / B / C | ✅ 14:07 | ☐ | ✅ gate M14 14:07 (19/19 files; m14: 23 + 15 + 24 checks, concurrency 5) | Core gate PASS, tag `core-v1` |
| M15-M18 | B48-B59 | Shared access layer / Notifications / Analytics | A / B / C | ✅ 14:20 | ☐ | ✅ gate M18 14:21 (24/24 files; m18: access 23, notif 16, dw 14) | `ddl/80_notif.sql`, `85_access.sql`, `90_dw.sql`; `docs/phase4/*`; RLS (D26), monthly delivery partitions (D27), SCD2 marts (D28); F3 fixed; tag `phase4` |
| M19 | B60-B64 | Seed (tablespace on D:) | B | ✅ 2026-10-15 | ☐ | ✅ rehearsal 33/33 (1.0 min); laptop scale 33/33 2026-10-16 | `seed/00-90`, `distributions.yaml`, `data_quality_issues.md`; 1M profiles, 100K jobs, 5M applications, 9.9M history rows, 11 GB, load 83 min; 0 FK orphans across 817 FKs; D30-D32 (D31 is a deviation: replica-mode load, re-proved by validation) |
| M20 | B65-B69 | Query set + validation | C, B | ✅ 2026-10-16 | ☐ | ✅ gate M20 11:11 (25/25 files) | `queries/Q01-Q13`, `perf/run_queries.ps1`, baseline p50/p95/p99 (30 runs) in `perf/results/baseline_laptop.csv`, plans in `perf/plans/`; report `docs/phase5/m20_queries.md` incl. seed validation 33/33 |
| M21 | B70-B74 | Performance + extrapolation | C | ✅ 2026-10-16 | ☐ | ✅ gate M21 11:20 (26/26 files) | baseline p50/p95/p99 at 1% and 100%; 11 index before/after experiments (10 modules justified, 20x-2290x; idx_notification_unread x1.1, D34); partitioning note D33; extrapolation: Q05 name substring degrades first (62 ms -> ~0.74 s at 10x, ~8.7 s at 100x); report `docs/phase5/m21_performance.md` |
| M22 | B75-B79 | Security | A | ✅ 2026-10-16 | ☐ | ✅ gate M22 12:35 (27/27 files; m22_privacy 36 checks) | `ddl/87_privacy.sql` (RLS on 15 more Personal tables, `anonymise_user`, `run_retention`), RLS performance fixes in `85_access.sql` (D36: skill search 80 s → 3.4 ms), `app.search_candidates_by_name`; security note + threat model `docs/phase5/m22_security.md`; D35-D37 |
| M23 | B80-B82 | Backup/restore + Gate 2 | All | ☐ | ☐ | ☐ | |

## M2 / M3 verification checklists
In `docs/phase1/entities.md` and `docs/phase1/relationships.md` (bottom of each file). Reviewer: C.

## M1 verification checklist (ticked by the AI pre-review; reviewer C confirms)
- [x] Every Section 4 domain (Tier 1 and 2) appears in exactly one module (`docs/01_module_list.md`)
- [x] Server settings recorded (`docs/04_environment.md`)
- [x] `.\run.ps1 gate M1` passes on a fresh database
- [x] Decisions doc covers engine, PK type, naming, schemas, delete classes, gig headline, central vs secondary workflows
