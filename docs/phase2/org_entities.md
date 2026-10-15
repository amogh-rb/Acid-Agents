# Organisation and account: entities (M7) — owner B

Backlogs B25, B28, B31, B34. DDL: `ddl/45_org.sql`. Tests: `tests/constraints/m10_org.sql`. Relationships: `docs/phase2/org_relationships.md`.

Entity rows were drafted from the DDL comments with `tools/draft_design_docs.py` and reviewed; `tests/docs/m07_phase2_docs.ps1` and the m05 comparison keep them equal to the catalog.

## Key rules
- Hierarchy: `ck_organisation_not_own_parent` + `trg_organisation_hierarchy` (recursive cycle guard, depth limit 100).
- Identifiers are Sensitive: written only through `org.add_identifier()`, which validates `ref.identifier_type.validation_regex`, encrypts with pgcrypto (key per session, held outside the database), and stores an HMAC hash plus the last 4. `uq_organisation_identifier_value_hash` stops the same GSTIN being registered twice.
- Recruiter mapping is effective-dated: `ex_recruiter_mapping_valid_range` (one organisation at a time per recruiter; back-to-back periods allowed).
- Verification requests carry an idempotency key and a unique provider reference (integration boundary).
- Accounts are the commercial customer (subscriptions and wallet in M14); an organisation may belong to an account.

## Entities
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| organisation | org | Organisation and account | Stub from Phase 1, extended here: Employer, client, consultancy or campus. Stub in Phase 1; extended by Organisation and account in M7-M10 | 1 | soft-delete | B |
| organisation_type | ref | Organisation and account | Lookup: kind of organisation. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| employee_count_band | ref | Organisation and account | Lookup: company size band. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| account_status | ref | Organisation and account | Lookup: commercial account status. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| verification_kind | ref | Organisation and account | Lookup: what an organisation verification checks. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| account | org | Organisation and account | Commercial account (customer) that owns one or more organisations, their subscriptions and wallet | 1 | soft-delete | B |
| organisation_location | org | Organisation and account | Office or site of an organisation (owned by the organisation) | 1 | hard-delete | B |
| organisation_identifier | org | Organisation and account | Tax or registration identifier (GSTIN, PAN, CIN, EIN) of an organisation; written through org.add_identifier, never in clear | 1 | hard-delete | B |
| verification | org | Organisation and account | One verification request to the company registration / tax service and its outcome (integration boundary, docket Section 6) | 1 | hard-delete | B |
| account_administrator | org | Organisation and account | User who administers a commercial account (owned by the account); at most one primary | 1 | hard-delete | B |
| recruiter_mapping | org | Organisation and account | Which organisation a recruiter works for, over which dates; periods for one recruiter never overlap (history kept by closing the period) | 1 | hard-delete | B |

## Validation checklist (reviewer ticks)
- [ ] Every domain of this module in docket Section 7 has an entity.
- [ ] No two entities hold the same fact; stubs are extended, not duplicated.
- [ ] Every enumeration has a `ref` (or module) lookup.
- [ ] `python tools/reserved_words.py` passes on this file.
