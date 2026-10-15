# Milestone status board

A milestone is done only when it is **Defined** (deliverable committed), **Verified** (someone other than the author ticked the checklist; initials and time), and **Tested** (`.\run.ps1 gate Mnn` prints PASS on a fresh database).
- Times are IST.
- Update this file in the same commit that closes the milestone.

| M | Backlogs | Scope | Owner | Defined | Verified (by, time) | Tested (gate, time) | Notes |
|---|---|---|---|---|---|---|---|
| M1 | B1-B3 | Provider, module list, build base | All | ✅ 12:25 | ☐ | ✅ gate M1 12:17 (72 checks) | Evidence: `docs/evidence/gate_M01_*.txt` |
| M2 | B4-B7 | Entities: Master data, Profile, Jobs | A, B | ☐ | ☐ | ☐ | |
| M3 | B8-B11 | Relationships + ERD + stubs | A, B | ☐ | ☐ | ☐ | |
| M4 | B12-B15 | Columns + comments + lookup seed | A, B | ☐ | ☐ | ☐ | |
| M5 | B16-B19 | Dictionary + generated ERD + design note | C | ☐ | ☐ | ☐ | |
| M6 | B20-B23 | Keys, constraints, transition trigger, Phase 1 sign-off | A, B | ☐ | ☐ | ☐ | Must pass by 13:20 |
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

## M1 verification checklist (reviewer ticks)
- [ ] Every Section 4 domain (Tier 1 and 2) appears in exactly one module (`docs/01_module_list.md`)
- [ ] Server settings recorded (`docs/02_environment.md`)
- [ ] `.\run.ps1 gate M1` passes on a fresh database
- [ ] Decisions doc covers engine, PK type, naming, schemas, delete classes, gig headline, central vs secondary workflows
