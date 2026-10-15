# 11 Coverage gap register (core gate, M14)

Every Tier 1/2 element of docket Section 4 not yet built, with its reason and the milestone that closes it. Status as of `core-v1` (M1-M14).

## Not built yet (planned)
| Element | Tier | Module | Why not yet | Closes in |
|---|---|---|---|---|
| Notifications and delivery status | 1 | Notifications | Phase 4 by plan; monthly-partitioned `notif.notification_delivery` | M15-M18 |
| Preferences: notification, language, job alert, privacy | 1 | Notifications | Phase 4 by plan | M15-M18 |
| Row-level security (recruiter sees own company's jobs; consultant sees open jobs; blocked party cannot see the candidate) | 1 (Section 3) | Shared access layer | The data it reads exists (`org.recruiter_mapping`, `admin.block_list`, `admin.user_role`); policies come in M18 | M15-M18 |
| Analytics star schema and KPI marts | 1 (Section 7) | Analytics | Phase 4 by plan; docket Section 8 (KPIs) has not been issued | M15-M18 |
| Community posts and reactions | 2 | Notifications | Phase 4 by plan (thin) | M15-M18 |
| Support tickets, FAQs | 2 | Notifications | Phase 4 by plan (thin) | M15-M18 |
| Seed data (1M profiles, 100K jobs, 5M applications) | Section 6 | All | Phase 5 by plan; tablespace on D: | M19 |
| Query set, performance, extrapolation | Section 6 | All | Phase 5 by plan | M20-M21 |
| Security note, threat model, access tests, backup/restore | Section 7 | All | Phase 5 by plan | M22-M23 |
| Retention purge job (anonymise on request, inactivity) | RG4 | All | Rules are stated per table comment; the scheduled process comes with security | M22 |

## Built with known limitations
| Item | Limitation | Plan |
|---|---|---|
| F3: an interviewer must belong to the job's organisation | Not enforced; recruiter mapping now exists | Trigger on `job.interview` using `org.current_recruiter_organisation` (M18) |
| F4: a screening answer's question must be on a questionnaire attached to the job | Not enforced | Trigger on `job.application_answer` (M15+) |
| Append-only event tables (views, activity, bookmarks, downloads, attempts, ledger, payment events) | Not partitioned yet | Leaf tables: monthly range partitioning decided with measurements (M21; D5) |
| d_money is numeric(14,2) | 3-decimal currencies would need numeric(14,3) | Accepted for the seeded currencies (D12) |
| Phase 2 and 3 design docs | Drafted from the DDL comments by the same agent that wrote the DDL (D21) | Human review by the module owners |

## Docket gaps (not ours)
- Sections 8 (KPIs), 10 (performance method, RTO) and 12 are referenced but were not issued. Ask the organisers before M15 (KPIs) and M21 (RTO).

## Tier 3 (optional stretch, not built)
Salary benchmarks, company ratings, trending job snapshots, dashboard aggregates, feature flags. If taken on, they become a separate stretch module (docket Section 7).
