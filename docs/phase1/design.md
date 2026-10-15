# Phase 1 design: profile and pipeline model (M5: B16-B19)

1. **One identity, one profile.** Every login is one `admin.app_user`; a candidate's `profile.candidate_profile` is 1:1 with it. The profile is soft-deleted and anonymised on request, never hard-deleted while history refers to it.
2. **The profile is a hub of owned children.** Contacts, addresses, identity documents, education, experience, skills, languages, certifications, projects, preferences, links and resume versions all hang off it with `ON DELETE CASCADE`, which fires only in the retention purge.
3. **Master data keeps profiles and jobs comparable.** The same `ref.skill`, `ref.qualification`, `ref.job_role`, `ref.city` and `ref.industry` rows are referenced from both sides. Free text (`employer_name`, `institution_name`) is kept only when the master list has no match, and in M6 a CHECK requires exactly one of the two.
4. **Unknown is not zero.** Salaries carry a `*_disclosure_code` (`disclosed` / `not_disclosed` / `not_applicable`). The amounts are NULL unless the code is disclosed. Money is always `d_money` plus a currency and a pay period.
5. **Sensitive identifiers are never stored.** `candidate_identity_document` keeps the verification service's token, an HMAC hash (for duplicate detection) and the last 4 characters only.
6. **A job is a `job.job_requirement` owned by an organisation.** The optional client covers agencies; positions are rows of `job_position`; skills, qualifications, locations and questionnaires are junction rows.
7. **One application per candidate per job.** `job.application` holds the current status and source. Every move is appended to `application_status_history` (append-only, with actor and time).
   - `application` is hash-partitioned on `candidate_profile_id` into 32 partitions (D5), so the unique key still holds.
   - Every child references it by `(application_id, candidate_profile_id)`.
8. **The pipeline is data, not code.** `application_status_transition` lists the legal moves (`applied` → `shortlisted` → `interviewed` → `offered` → `joined`, with `rejected` and `withdrawn` exits). The M6 trigger rejects anything else, such as `applied` → `joined`.
9. **Interview, offer and joining are child tables** because each carries its own data (schedule and outcome; CTC and validity; joining dates). Rejection is a status plus a `rejection_reason` code, not a table.
10. **History is append-only and attributable.** Profile views, bookmarks, activity, searches and status changes are insert-only rows with actor, subject and time.
    - They are not partitioned in Phase 1. No FK points at them, so monthly range partitioning stays a cheap change, decided in M21 with measurements.
    - `application` was partitioned now because six FKs point at it.

**Generated vs hand-drawn ERD:** `docs/erd/phase1_generated.mmd` (from the catalog) and `docs/erd/phase1.mmd` (from `relationships.md`) describe the same 166 foreign keys. `tests/docs/m05_design_vs_catalog.ps1` proves this on every gate:
- every entity is a table with the same delete class;
- every documented FK exists with the same target, ON DELETE and nullability;
- no undocumented table or FK exists.

Differences recorded: none open. Four FKs found by the comparison during M5 (`ui_translation` x2, `description_language_id` x2) were added to `relationships.md`.
