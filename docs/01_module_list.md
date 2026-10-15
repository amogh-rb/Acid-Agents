# 01 Module list and assignments (M1: B2, B3)

Team: **A**, **B** and **C** (three members). The docket allows 3 to 5; with three people, the Delivery Plan's "Lead" role and Master data fold into A, and C takes the tooling.

## Modules (11 + optional stretch)

| # | Module | Type | Schema | Milestones | Owner | Reviewer |
|---|---|---|---|---|---|---|
| 1 | Master data | Common (Phase 1) | `ref` | M2-M6 | A | C |
| 2 | Profile | Common (Phase 1) | `profile` | M2-M6 | A | C |
| 3 | Jobs and Applications | Common (Phase 1) | `job` | M2-M6 | B | C |
| 4 | Administration | Individual (Phase 2) | `admin`, `audit` | M7-M10 | A | C |
| 5 | Organisation and account | Individual (Phase 2) | `org` | M7-M10 | B | A |
| 6 | Gig marketplace | Individual (Phase 2) | `gig` | M7-M10 | C | B |
| 7 | Licences, seats, devices and sessions | Individual (Phase 3) | `lic`, `app` | M11-M14 | A | C |
| 8 | Sourcing and consultant requests | Individual (Phase 3) | `src` | M11-M14 | B | A |
| 9 | Subscriptions, wallet, payments and download history | Individual (Phase 3) | `billing` | M11-M14 | C | B |
| 10 | Notifications, preferences and community | Individual (Phase 4) | `notif` | M15-M18 | B | - |
| 11 | Analytics layer and reporting marts | Individual (Phase 4) | `dw` | M15-M18 | C | - |
| S | Market reference (optional stretch, Tier 3) | Stretch | `mkt` (if built) | after M23 | - | - |

Phase 4 also has "shared team items" (B50-B59), owned by A:
- The tables themselves (credentials, consent, identity sessions, audit trail, blocking lists) are built in Administration (M7-M10).
- M15-M18 adds the access layer on top: RLS policies, group roles, grants, and the rule that a blocked party can't see the candidate.

The tooling (`run.ps1`, lint, dictionary, ERD) is owned by C.

## Section 4 domains: each owned by exactly one module

| Docket domain (Section 4) | Tier | Owning module | Main entities (planned) |
|---|---|---|---|
| Identity and accounts: users, credentials, roles, sessions, consent records | 1 | Administration | app_user, user_credential, app_role, permission, app_role_permission, user_role, consent_record. Identity sessions are referenced; device sessions are in Licences |
| Candidate profile core: personal, contact, education, experience, skills, languages | 1 | Profile | candidate_profile, candidate_contact, candidate_address, candidate_education, candidate_work_experience, candidate_skill, candidate_language |
| Employer and client organisation: details, locations, tax/registration ids, verification, mapped recruiters | 1 | Organisation and account | organisation, organisation_location, organisation_identifier, verification, recruiter_mapping |
| Job requirement lifecycle: posting, status, positions, requirements, publish state, consultant openness | 1 | Jobs and Applications | job_requirement, job_position, job_requirement_skill, job_requirement_qualification, job_requirement_location |
| Applications and pipeline: applied ... joined, rejected | 1 | Jobs and Applications | application, application_status_history, application_status_transition, interview, offer, joining |
| Sourcing and consultant requests: requests, accept/decline, candidate shortlists | 1 | Sourcing | sourcing_request, sourcing_shortlist (references `job.shortlist`) |
| Wallet and credits: balances, recharges, consumption, transactions | 1 | Subscriptions/wallet | wallet, wallet_ledger_entry, credit_consumption |
| Audit and error logging | 1 | Administration | audit.audit_event, audit.error_log |
| Master data: cities, states, countries, skills, qualifications, industries, job roles, employment and work types | 1 | Master data | country, state, city, skill, qualification, industry, job_role, employment_type, work_type, plus every lookup |
| Notifications and alert preferences | 1 | Notifications | notification, notification_delivery, notification_preference |
| Gig marketplace | 1 | Gig marketplace | gig_request, gig_worker_profile, gig_availability, gig_application, gig_assignment, gig_fulfilment_handoff, gig_earning_reference, gig_requester_worker_list, gig_rating |
| Licences and seats | 1 | Licences | licence, licence_seat |
| Devices and sessions: devices, active sessions, login history, device-limit rule | 1 | Licences | registered_device, login_session, login_attempt, session_revocation |
| Subscriptions and plans | 1 | Subscriptions/wallet | plan, plan_entitlement, subscription, subscription_renewal, subscription_cancellation |
| Payments and transaction history | 1 | Subscriptions/wallet | payment_order, payment_event, invoice, refund (and the ledger above) |
| Account and organisation: account profiles, account admins, status, hierarchy | 1 | Organisation and account | account, account_administrator, organisation.parent_organisation_id |
| Preferences: notification, language, job alert, privacy | 1 | Notifications | notification_preference, job_alert_preference, language_preference, privacy_setting |
| Profile projects: candidate projects and gig projects | 1 | Profile | candidate_project (`project_kind`: employment, academic, gig; gig projects may reference a gig assignment) |
| Profile download history | 1 | Subscriptions/wallet | profile_download_event (references its ledger debit) |
| Resume versions and templates | 2 | Profile | resume_template, resume_version |
| Community posts and reactions | 2 | Notifications | community_post, community_reaction |
| Assessments and scores | 2 | Profile | assessment, assessment_attempt |
| Course enrolments | 2 | Profile | course, course_enrolment |
| Support tickets | 2 | Notifications | support_ticket, support_ticket_message |
| FAQs | 2 | Notifications | faq |
| Referral tracking (incl. referral events) | 2 | Profile | referral. Notifications only sends referral messages and owns no referral table |
| Blocking lists | 2 | Administration | block_list |
| Profile completion scoring | 2 | Profile | profile_completion_score |
| Profile view history | 2 | Profile | profile_view_event |
| Job search and application history | 2 | Jobs and Applications | job_search_event, saved_search (application history = application_status_history) |
| Candidate activity log | 2 | Profile | candidate_activity_event |
| Shortlist history | 2 | Jobs and Applications | shortlist, shortlist_entry |
| Bookmark history | 2 | Profile | candidate_bookmark_event |
| Salary benchmarks, company ratings, trending job snapshots, dashboard aggregates, feature flags | 3 | Stretch (or `dw` aggregates) | Optional; recorded in `11_coverage_gap_register.md` if not built |

**Settled overlaps**
- The docket lists "referral tracking" under Profile and "referral events" under Notifications. **Profile owns referral data.**
- "Shortlist and bookmark history" is split: the shortlist belongs to Jobs (the Sourcing module references it), and bookmark history belongs to Profile.
- Identity sessions (Administration) vs device sessions (Licences): there is one session table, `lic.login_session`, owned by Licences. Administration references it for identity.
