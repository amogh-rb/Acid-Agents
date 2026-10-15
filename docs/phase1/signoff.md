# Phase 1 sign-off (B23)

**Scope:** Master data (`ref`), Profile (`profile`), Jobs and Applications (`job`), and the stubs `admin.app_user` and `org.organisation`.

**Evidence:** `.\run.ps1 gate M6` on a fresh database → **PASS, 8/8 files** (M6: 41 checks). Output is in `docs/evidence/` (latest `test_*.txt`).

## What was built
- **96 tables:** 50 ref, 24 profile, 20 job, 2 stubs.
- **1,000 columns.** Every one has a domain, a sensitivity class and (when nullable) a reason.
- **`job.application` hash-partitioned** on `candidate_profile_id` into 32 partitions (D5). The FKs into it are composite.
- **166 documented foreign keys:**
  - each has an ON DELETE rule;
  - they are proven equal to the catalog by the m05 test;
  - none in the database is undocumented.
- **Pipeline rules in the database:**
  - legal transitions are a data table, enforced by `trg_application_status_transition`;
  - every change is written to the append-only `application_status_history` with its actor.

## Rule 2 checklist (reviewer ticks)
| Check | Constraint(s) | Test |
|---|---|---|
| [ ] Date ranges | `ck_candidate_education_date_range`, `ck_candidate_work_experience_date_range`, `ck_candidate_project_date_range`, `ck_candidate_certification_date_range`, `ck_course_enrolment_date_range`, `ck_interview_schedule`, `ck_offer_valid_until` | m06 #3, interview schedule |
| [ ] Salary min ≤ max | `ck_job_requirement_salary_range` | m06 #1 |
| [ ] Experience min ≤ max | `ck_job_requirement_experience_range` | m06 |
| [ ] Disclosure code ↔ NULL amounts | `ck_job_requirement_salary_disclosure`, `ck_candidate_profile_current_salary_disclosure`, `..._expected_salary_disclosure`, `ck_candidate_profile_salary_currency` | m06 #2, profile currency |
| [ ] One application per candidate and job | `uq_application_candidate_profile_id_job_requirement_id` | m06 #4 |
| [ ] Unique lowercase contact email | `ck_d_email_lowercase` (domain) + `uq_candidate_contact_email` | m06 #8a, #8b |
| [ ] Legal status transitions only | `trg_application_status_transition` + `job.application_status_transition` | m06 #5, on-hold job, terminal joined |
| [ ] Status history append-only | `trg_application_status_history_forbid_update_delete` + revoked grants | m06 #6a, #6b |
| [ ] No free-text enumerations | FKs to `ref.*(code)` | m06 #7a, #7b |
| [ ] Job with applications cannot be deleted | `fk_application_job_requirement_id` (RESTRICT) | m06 #9 |
| [ ] Partial index on open, published, live jobs | `idx_job_requirement_open_published` | catalog (dictionary) |
| [ ] Cross-row integrity | `fk_joining_offer_id_application_id`, `fk_job_position_filled_by_application` and the `fk_<child>_application` composites `(application_id, candidate_profile_id)` | m06 |
| [ ] Partitioning (D5) | `PARTITION BY HASH (candidate_profile_id)`, 32 partitions, PK `(id, candidate_profile_id)` | m06 (partition key, 32 partitions, row routing) |

## Deviations from the Milestone Plan test list
- **Test 8** ("duplicate contact email in a different case") is proven in two steps:
  - The lowercase domain stops a mixed-case email from being stored at all (`ck_d_email_lowercase`).
  - The unique constraint stops the lowercase duplicate (`uq_candidate_contact_email`).
  - The unique key cannot be reached by a mixed-case value because the domain check fires first. This is stronger than a case-insensitive index (D2).
- **Test 7** uses an `imported` application, because the transition trigger (a BEFORE trigger) rejects a free-text status on normal inserts before the FK is checked. Both rejections are valid; 7b shows the FK on the history table directly.
- **Test 4 on the partitioned table:** PostgreSQL reports the partition's own index (`application_hNN_..._key`). `qa.expect_error` maps it to its parent constraint `uq_application_candidate_profile_id_job_requirement_id` through `pg_partition_ancestors` and prints both.
- **Keys in M4:** PKs and FKs were declared in M4 (D13). M6 added unique, check, composite-FK, trigger and index rules.

## Sign-off
| Role | Name | Time (IST) | Signature |
|---|---|---|---|
| Reviewer (C) | | | |
| Author, Profile (A) | | | |
| Author, Jobs (B) | | | |
