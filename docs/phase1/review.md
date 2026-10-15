# Phase 1 review (M1-M6): AI pre-review

**Reviewer:** Claude (AI), 2026-10-15 13:07 IST.

**Independence:** none. The same agent authored the design, so this review does not satisfy the plan's "someone other than the author" rule. Reviewer C must still confirm and sign `signoff.md`.

**Method:** every checklist was walked against the live catalog (not the docs), using queries R1-R7 below, after a fresh `run.ps1 up`. Fixes were re-proved by `.\run.ps1 test` → PASS 8/8 (evidence `docs/evidence/test_20261015_1306.txt`).

## Checks run against the catalog
| # | Check | Result |
|---|---|---|
| R1 | Every `ON DELETE CASCADE` FK is an owned child | **Pass.** 25 CASCADE FKs: profile children, job junctions, questionnaire parts, application_answer, shortlist_entry, ui_translation. The extra rows are the per-partition clones PostgreSQL creates for FKs into a partitioned table |
| R2 | SET NULL used only where justified | **Pass.** Exactly one: `candidate_project.candidate_work_experience_id` |
| R3 | No FK leaves Phase 1 except to the stubs | **Pass.** Outside targets: only `admin.app_user`, `org.organisation` |
| R4 | No free-text enumerations | **Pass.** Only `resume_version.file_mime_type` (IANA registry, open-ended; not a fixed set) and `application_status_history.change_reason` (free note) |
| R5 | FK columns on large tables are indexed | **Fail → fixed (see F2)** |
| R6 | Partial index on open, published, live jobs | **Pass.** `idx_job_requirement_open_published` with predicate status = open AND publish_state = published AND deleted_at IS NULL |
| R7 | Tables without a natural unique key | **Accepted.** Addresses, experience, certifications, projects (a person may legitimately repeat them), the append-only event tables, and referral (re-invites are allowed) |
| — | Section 4 domains, each in exactly one module | **Pass** (`01_module_list.md`; overlaps settled: referral → Profile, shortlist → Jobs, bookmark history → Profile, sessions → Licences) |
| — | Profile and Jobs domains from Section 7 each have entities | **Pass.** All 14 Profile and 12 Jobs domains map to entities (`entities.md` checklist) |
| — | Every many-to-many has a junction | **Pass.** 11 junctions (`relationships.md`) |
| — | Rule 2 list (date ranges, salary, experience, disclosure, unique application, unique email) | **Pass.** Each is a named constraint with a failing test in m06 |
| — | Server settings recorded | **Pass** (`04_environment.md`; tuning still to apply before M21) |

## Findings
| ID | Severity | Finding | Action |
|---|---|---|---|
| F1 | High | `application.resume_version_id` only checked that the resume exists, so an application could carry another candidate's resume | **Fixed.** `uq_resume_version_id_candidate_profile_id` + composite `fk_application_resume_version_owner (resume_version_id, candidate_profile_id)`; m06 test rejects it and accepts the applicant's own |
| F2 | Medium | FK columns without a supporting index on large or purge-path tables. Worst: `candidate_project.candidate_work_experience_id` (SET NULL scans the whole table on every experience delete); also view events by viewer, application by resume/referral, referral by referred profile and job, job postings by recruiter/client, interviews by interviewer, shortlists, bookmarks by job, attempts by assessment, resumes by template | **Fixed.** 15 indexes (partial where the column is nullable). The composite FKs into `job.application` already have a leading `application_id` index |
| F3 | Medium (deferred) | An interviewer is not checked to belong to the job's organisation | Needs recruiter mapping (M10, Organisation). Add to M10 or M18 (RLS) |
| F4 | Medium (deferred) | `application_answer.questionnaire_question_id` is not checked to belong to a questionnaire attached to the application's job | A trigger can do it. Logged for M15+ or as a Phase 1 follow-up if time allows |
| F5 | Low | `uq_candidate_contact_email` is global, so a soft-deleted profile still holds its email until anonymisation | By design: the deletion workflow anonymises Personal columns (M22). Documented here |
| F6 | Info | `job.application.id` is unique by its identity sequence, not by a constraint on id alone (partitioned table) | Recorded in D5 |

## Verdict
Phase 1 meets the M1-M6 checklists after fixes F1 and F2. F3 and F4 are known gaps with an owner milestone. Ready for reviewer C's confirmation and signature.
