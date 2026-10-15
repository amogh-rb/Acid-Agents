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
| M7 | B24-B26 | Entities: Admin / Org / Gig | A / B / C | ☐ | ☐ | ☐ | |
| M8 | B27-B29 | Relationships: Admin / Org / Gig | A / B / C | ☐ | ☐ | ☐ | |
| M9 | B30-B32 | Columns: Admin / Org / Gig | A / B / C | ☐ | ☐ | ☐ | |
| M10 | B33-B35 | Keys and constraints + tests: Admin / Org / Gig | A / B / C | ☐ | ☐ | ☐ | Tag `phase2` |
| M11 | B36-B38 | Entities: Licences / Sourcing / Subscriptions | A / B / C | ☐ | ☐ | ☐ | |
| M12 | B39-B41 | Relationships | A / B / C | ☐ | ☐ | ☐ | |
| M13 | B42-B44 | Columns | A / B / C | ☐ | ☐ | ☐ | |
| M14 | B45-B47 | Keys and constraints + tests (incl. 20-login concurrency) | A / B / C | ☐ | ☐ | ☐ | Core gate, tag `core-v1` |
| M15-M18 | B48-B59 | Shared access layer / Notifications / Analytics | A / B / C | ☐ | ☐ | ☐ | |
| M19 | B60-B64 | Seed (tablespace on D:) | B | ☐ | ☐ | ☐ | |
| M20 | B65-B69 | Query set + validation | C, B | ☐ | ☐ | ☐ | |
| M21 | B70-B74 | Performance + extrapolation | C | ☐ | ☐ | ☐ | |
| M22 | B75-B79 | Security | A | ☐ | ☐ | ☐ | |
| M23 | B80-B82 | Backup/restore + Gate 2 | All | ☐ | ☐ | ☐ | |

## M2 / M3 verification checklists
In `docs/phase1/entities.md` and `docs/phase1/relationships.md` (bottom of each file). Reviewer: C.

## M1 verification checklist (ticked by the AI pre-review; reviewer C confirms)
- [x] Every Section 4 domain (Tier 1 and 2) appears in exactly one module (`docs/01_module_list.md`)
- [x] Server settings recorded (`docs/04_environment.md`)
- [x] `.\run.ps1 gate M1` passes on a fresh database
- [x] Decisions doc covers engine, PK type, naming, schemas, delete classes, gig headline, central vs secondary workflows
