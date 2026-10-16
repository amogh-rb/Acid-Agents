# 11 Coverage gap register (updated at each phase gate; current: M22)

Every Tier 1/2 element of docket Section 4 not yet built, with its reason and the milestone that closes it. Status as of `phase4` (M1-M18).

**Closed in M22:** retention job and anonymisation (D35, D37), RLS on every Personal table of the profile, RLS performance at 1M profiles (D36).

**Closed in M19:** laptop-scale seed (1M profiles, 100K jobs, 5M applications), validated by 33 checks (D30-D32).

**Closed in M15-M18:** notifications and delivery status, all preferences (notification, job alert, language, privacy), RLS access layer, analytics star schema and KPI marts, community posts and reactions, support tickets, FAQs, review finding F3.

## Not built yet (planned)
| Element | Tier | Module | Why not yet | Closes in |
|---|---|---|---|---|
| Query set, performance, extrapolation | Section 6 | All | Phase 5 by plan | M20-M21 |
| Security note, threat model, access tests, backup/restore | Section 7 | All | Phase 5 by plan | M22-M23 |

## Built with known limitations
| Item | Limitation | Plan |
|---|---|---|
| F4: a screening answer's question must be on a questionnaire attached to the job | Not enforced | Trigger on `job.application_answer` (M15+) |
| Append-only event tables (views, activity, bookmarks, downloads, attempts, ledger, payment events) | Not partitioned yet (notification deliveries are, D27) | Leaf tables: monthly range partitioning decided with measurements (M21; D5) |
| KPIs | Docket Section 8 not issued; the marts serve assumed KPIs (D28) | Adjust `dw` when the KPI list arrives |
| d_money is numeric(14,2) | 3-decimal currencies would need numeric(14,3) | Accepted for the seeded currencies (D12) |
| Phase 2 and 3 design docs | Drafted from the DDL comments by the same agent that wrote the DDL (D21) | Human review by the module owners |

| Personal tables outside RLS (application answers, interview feedback, offers, gig worker data, tickets, referrals) | Grants only | Same `candidate_profile_visible` pattern when exposed directly (M22 open item) |
| Actor identity is set by the application (`app.current_user_id`) | Not verified by the database (threat T3) | Session-token-verified actor function (M22 open item) |

## Docket gaps (not ours)
- Sections 8 (KPIs), 10 (performance method, RTO) and 12 are referenced but were not issued. Ask the organisers before M15 (KPIs) and M21 (RTO).

## Tier 3 (optional stretch, not built)
Salary benchmarks, company ratings, trending job snapshots, dashboard aggregates, feature flags. If taken on, they become a separate stretch module (docket Section 7).
