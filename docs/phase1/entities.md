# Phase 1 entities (M2: B4-B7)

Scope: Master data (`ref`), Profile (`profile`), Jobs and Applications (`job`), and the two cross-module stubs that Phase 1 FKs point at.
- Starting point: Delivery Plan section 4. Additions are marked **+** in the purpose column, with the reason.
- Delete classes are explained in `docs/00_decisions.md` §6. Lookups are hard-delete in principle; once a row is referenced, FK RESTRICT blocks the delete and the row is deactivated with `is_active` instead.
- Tier: 1 = mandatory, 2 = expected, 3 = optional (docket Section 4); "ref" = reference data supporting a tier.

## Stubs (cross-module anchors)

Created in `ddl/15_stubs.sql` with only an id, a status, the audit columns and the minimum needed for Phase 1. The Phase 2 owners extend them with `ALTER TABLE`, so no Phase 1 FK needs rework. `job_requirement` and `candidate_profile` are full Phase 1 entities below; they are the anchors that later modules (sourcing, billing, gig, analytics) reference.

| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| app_user | admin | Administration | One row per login identity (candidate, recruiter, consultant, admin, system); actor for every created_by/updated_by | 1 | soft-delete | A |
| organisation | org | Organisation and account | Employer, client, consultancy or campus; owner of job requirements, questionnaires and shortlists | 1 | soft-delete | B |

## Master data (`ref`), owner A

### Geography, language, currency
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| country | ref | Master data | ISO 3166 country; phone country and nationality | 1 | hard-delete | A |
| state | ref | Master data | First-level subdivision (state, province) within a country | 1 | hard-delete | A |
| city | ref | Master data | City or town; job locations, addresses, preferred locations; optional coordinates | 1 | hard-delete | A |
| timezone | ref | Master data | IANA time zone, used to display UTC timestamps (RG3 Timestamp) | ref | hard-delete | A |
| currency | ref | Master data | ISO 4217 currency; FK target of every money companion column | 1 | hard-delete | A |
| language | ref | Master data | UI, profile and content languages; exactly one default (built in M1) | 1 | hard-delete | A |
| ui_label | ref | Master data | UI string key (built in M1) | 1 | hard-delete | A |
| ui_translation | ref | Master data | Translation of one key into one language (built in M1) | 1 | hard-delete | A |

### Skills, education, industry, roles
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| skill_category | ref | Master data | Hierarchical grouping of skills (Programming > Backend) | 1 | hard-delete | A |
| skill | ref | Master data | Canonical skill (PostgreSQL, Welding, Tally); shared by profiles, jobs, assessments and courses | 1 | hard-delete | A |
| qualification_level | ref | Master data | Lookup: secondary, higher secondary, diploma, bachelor, master, doctorate, certificate | 1 | hard-delete | A |
| qualification | ref | Master data | Named qualification (B.Tech, ITI Fitter, MBA) at a level | 1 | hard-delete | A |
| field_of_study | ref | Master data | Specialisation (Computer Science, Mechanical) | 1 | hard-delete | A |
| institution | ref | Master data | School, college or university; campus hiring and education records | 1 | hard-delete | A |
| industry | ref | Master data | Hierarchical industry classification for employers, jobs and experience | 1 | hard-delete | A |
| job_function | ref | Master data | Department or function (Engineering, Sales, Operations) | 1 | hard-delete | A |
| job_role | ref | Master data | Standard role within a function (Backend Developer, Forklift Operator) | 1 | hard-delete | A |
| identifier_type | ref | Master data | **+** National and tax identifier types (Aadhaar, PAN, passport, GSTIN, CIN) with a validation regex and whether each applies to a person or an organisation. Shared by Profile and Organisation | 1 | hard-delete | A |

### Enumeration lookups (built with `ref.create_lookup`: code, label_key, is_active, sort_order)
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| user_status | ref | Master data | **+** app_user status: pending_verification, active, suspended, deactivated (needed by the stub) | 1 | hard-delete | A |
| organisation_status | ref | Master data | **+** organisation status: pending_verification, active, suspended, closed (needed by the stub) | 1 | hard-delete | A |
| verification_status | ref | Master data | **+** Outcome of an external verification: pending, verified, failed, expired | 1 | hard-delete | A |
| employment_type | ref | Master data | Permanent, contract, temporary, apprentice, internship, freelance | 1 | hard-delete | A |
| work_type | ref | Master data | Onsite, remote, hybrid | 1 | hard-delete | A |
| job_category | ref | Master data | Gig, general staffing, professional staffing, permanent, apprentice, campus, consultant marketplace, managed remote | 1 | hard-delete | A |
| disclosure | ref | Master data | Unknown vs not applicable (RG5): disclosed, not_disclosed, not_applicable. Ties to NULL amounts by CHECK. Named `disclosure_code` in the Milestone Plan; the table is `disclosure` and columns end in `_disclosure_code` | 1 | hard-delete | A |
| pay_period | ref | Master data | **+** Period a salary or rate is quoted in: annual, monthly, daily, hourly | 1 | hard-delete | A |
| notice_period | ref | Master data | Immediate, 15, 30, 60, 90 days, serving notice | 1 | hard-delete | A |
| proficiency_level | ref | Master data | Beginner, intermediate, advanced, expert (skills); also used for languages | 1 | hard-delete | A |
| gender | ref | Master data | **+** Self-described gender including prefer_not_to_say (personal details) | 1 | hard-delete | A |
| contact_type | ref | Master data | **+** email, phone, whatsapp | 1 | hard-delete | A |
| address_type | ref | Master data | **+** current, permanent, correspondence | 1 | hard-delete | A |
| study_mode | ref | Master data | **+** full_time, part_time, distance, online | 1 | hard-delete | A |
| project_kind | ref | Master data | **+** employment, academic, personal, gig (profile projects cover candidate and gig projects) | 1 | hard-delete | A |
| web_link_type | ref | Master data | **+** linkedin, github, portfolio, other (exceeds Naukri/Monster coverage) | 2 | hard-delete | A |
| assessment_type | ref | Master data | **+** self_assessment, skill_test, aptitude, language | 2 | hard-delete | A |
| enrolment_status | ref | Master data | **+** enrolled, in_progress, completed, dropped | 2 | hard-delete | A |
| referral_status | ref | Master data | **+** invited, registered, applied, hired, expired | 2 | hard-delete | A |
| activity_event_type | ref | Master data | **+** login, profile_update, resume_download, resume_upload, job_apply, password_change | 2 | hard-delete | A |
| bookmark_action | ref | Master data | **+** added, removed (bookmark history is append-only) | 2 | hard-delete | A |
| job_requirement_status | ref | Master data | Lifecycle: draft, open, on_hold, closed, filled, cancelled (Milestone Plan: `job_status`) | 1 | hard-delete | A |
| publish_state | ref | Master data | Visibility: unpublished, scheduled, published, expired, withdrawn | 1 | hard-delete | A |
| application_status | ref | Master data | Pipeline: applied, shortlisted, interviewed, offered, joined, rejected, withdrawn | 1 | hard-delete | A |
| application_source | ref | Master data | **+** direct, sourced, referral, campus, consultant, imported | 1 | hard-delete | A |
| rejection_reason | ref | Master data | Why an application was rejected (skills_mismatch, salary_mismatch, no_show ...) | 1 | hard-delete | A |
| question_type | ref | Master data | **+** single_choice, multi_choice, short_text, numeric, yes_no | 1 | hard-delete | A |
| interview_mode | ref | Master data | In person, video, phone | 1 | hard-delete | A |
| interview_status | ref | Master data | **+** scheduled, completed, cancelled, no_show, rescheduled | 1 | hard-delete | A |
| interview_outcome | ref | Master data | **+** passed, failed, on_hold | 1 | hard-delete | A |
| offer_status | ref | Master data | extended, accepted, declined, withdrawn, expired | 1 | hard-delete | A |
| joining_status | ref | Master data | **+** expected, joined, no_show, deferred | 1 | hard-delete | A |

## Profile (`profile`), owner A

| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| candidate_profile | profile | Profile | Candidate personal details, headline, summary, experience, current/expected salary with disclosure; 1:1 with app_user | 1 | soft-delete | A |
| candidate_contact | profile | Profile | Email, phone and WhatsApp contact points; one primary per type; unique lowercase email | 1 | hard-delete | A |
| candidate_address | profile | Profile | Current, permanent or correspondence address with city and optional coordinates | 1 | hard-delete | A |
| candidate_identity_document | profile | Profile | **+** National identity reference from the verification service: token, masked last 4 and outcome; never the raw number (Section 6) | 1 | hard-delete | A |
| candidate_language | profile | Profile | Languages the candidate knows, with proficiency | 1 | hard-delete | A |
| candidate_education | profile | Profile | Education history: qualification, field, institution, dates, score | 1 | hard-delete | A |
| candidate_work_experience | profile | Profile | Employment history: employer, role, industry, dates, current-job flag | 1 | hard-delete | A |
| candidate_skill | profile | Profile | Candidate-to-skill junction with proficiency and years used | 1 | hard-delete | A |
| candidate_certification | profile | Profile | **+** Certifications with issuer, issue/expiry dates and credential id (LinkedIn parity) | 1 | hard-delete | A |
| candidate_project | profile | Profile | Candidate and gig projects with role, duration and outcome (Tier 1 "Profile projects") | 1 | hard-delete | A |
| candidate_preferred_location | profile | Profile | Cities the candidate wants to work in | 1 | hard-delete | A |
| candidate_preferred_role | profile | Profile | Job roles the candidate is looking for | 1 | hard-delete | A |
| candidate_web_link | profile | Profile | **+** Portfolio, GitHub and LinkedIn links | 2 | hard-delete | A |
| resume_template | profile | Profile | Platform resume layouts candidates build from | 2 | hard-delete | A |
| resume_version | profile | Profile | Each saved resume (built or uploaded) with body, language and file reference | 2 | soft-delete | A |
| assessment | profile | Profile | Assessment catalogue entry (self-assessment, skill test) linked to a skill | 2 | hard-delete | A |
| assessment_attempt | profile | Profile | One attempt by a candidate with score and percentile; history kept | 2 | append-only | A |
| course | profile | Profile | Course catalogue entry linked to a skill | 2 | hard-delete | A |
| course_enrolment | profile | Profile | Candidate enrolment in a course with status and completion date | 2 | hard-delete | A |
| profile_completion_score | profile | Profile | Current completion percentage and the missing sections; one row per profile, recomputed on change | 2 | hard-delete | A |
| profile_view_event | profile | Profile | Which employer or recruiter viewed which profile, and when | 2 | append-only | A |
| candidate_activity_event | profile | Profile | Candidate login, profile update and resume download events | 2 | append-only | A |
| candidate_bookmark_event | profile | Profile | Bookmark added or removed by an employer or recruiter (bookmark history) | 2 | append-only | A |
| referral | profile | Profile | Who referred whom (optionally for a job) and how far it progressed | 2 | hard-delete | A |

## Jobs and Applications (`job`), owner B

| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| job_requirement | job | Jobs and Applications | Job posting: organisation and client, category, type, role, salary with disclosure, experience range, status, publish state, consultant openness | 1 | soft-delete | B |
| job_position | job | Jobs and Applications | One opening within a requirement and its fill state (positions count = rows) | 1 | hard-delete | B |
| job_requirement_location | job | Jobs and Applications | Cities a requirement is open in | 1 | hard-delete | B |
| job_requirement_skill | job | Jobs and Applications | Skills required, mandatory or nice-to-have, with minimum proficiency | 1 | hard-delete | B |
| job_requirement_qualification | job | Jobs and Applications | Qualifications accepted for a requirement | 1 | hard-delete | B |
| questionnaire | job | Jobs and Applications | Reusable screening questionnaire owned by an organisation | 1 | hard-delete | B |
| questionnaire_question | job | Jobs and Applications | Ordered question in a questionnaire, with type and mandatory flag | 1 | hard-delete | B |
| question_option | job | Jobs and Applications | Allowed answer for a choice question | 1 | hard-delete | B |
| job_requirement_questionnaire | job | Jobs and Applications | Attaches questionnaires to a requirement | 1 | hard-delete | B |
| application | job | Jobs and Applications | Candidate applies to a requirement: current status, source, resume used, applied_at; one per candidate per job | 1 | soft-delete | B |
| application_answer | job | Jobs and Applications | Candidate answer to a screening question | 1 | hard-delete | B |
| application_status_history | job | Jobs and Applications | Every status transition with actor, time and reason (application history) | 1 | append-only | B |
| application_status_transition | job | Jobs and Applications | Legal (from, to) status moves; the transition trigger reads it | 1 | hard-delete | B |
| shortlist | job | Jobs and Applications | Named shortlist owned by an organisation, optionally for one requirement (Sourcing references it) | 2 | hard-delete | B |
| shortlist_entry | job | Jobs and Applications | Candidate on a shortlist; removal sets deleted_at, so shortlist history is kept | 2 | soft-delete | B |
| interview | job | Jobs and Applications | Interview round for an application: mode, schedule, interviewer, status, outcome | 1 | hard-delete | B |
| offer | job | Jobs and Applications | Offer made on an application: CTC with currency, joining date, status | 1 | hard-delete | B |
| joining | job | Jobs and Applications | Joining against an accepted offer: expected/actual date, status | 1 | hard-delete | B |
| saved_search | job | Jobs and Applications | Candidate's saved job search criteria | 2 | hard-delete | B |
| job_search_event | job | Jobs and Applications | Each job search a candidate or guest ran (search history) | 2 | append-only | B |

## Validation checklist (B5, B7: reviewer C ticks)

- [ ] **Coverage:** every Profile and Jobs domain in the docket Section 7 module table has at least one entity.
  - **Profile:** identity and contact (candidate_profile, candidate_contact, candidate_identity_document); education; work experience; skills; languages; resume versions and templates; profile projects; assessments and scores; course enrolments; profile completion scoring; profile view history; candidate activity log; bookmark history; referral tracking.
  - **Jobs:** job requirements; positions; questionnaires; publish state; applications; status pipeline; shortlists; interviews; offers; joins; rejections (status + rejection_reason); job search history (job_search_event, saved_search); application history (application_status_history).
- [ ] **No two entities hold the same fact.**
  - Rejection is a status plus `rejection_reason`, not a table.
  - Positions count is the number of `job_position` rows, not a column.
  - Current status lives on `application`, and the full history lives in `application_status_history`; the trigger keeps them in step.
  - Identity sessions are not duplicated here (Licences owns `login_session`).
- [ ] **Shared ownership settled:** `shortlist` and `shortlist_entry` belong to Jobs (Sourcing references them); `candidate_bookmark_event` belongs to Profile; `referral` belongs to Profile; `identifier_type` is master data used by Profile and Organisation.
- [ ] **Every enumeration has its own `ref` lookup:** every fixed value set above is listed under "Enumeration lookups", plus qualification_level and identifier_type. No free-text status or type columns.
- [ ] **Names checked:** `python tools/reserved_words.py docs/phase1/entities.md` passes (`gate M2`).
