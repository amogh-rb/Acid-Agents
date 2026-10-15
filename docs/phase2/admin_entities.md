# Administration: entities (M7) — owner A

Backlogs B24, B27, B30, B33. DDL: `ddl/40_admin.sql`. Tests: `tests/constraints/m10_admin.sql`. Relationships: `docs/phase2/admin_relationships.md`.

Entity rows were drafted from the DDL comments with `tools/draft_design_docs.py` and reviewed; `tests/docs/m07_phase2_docs.ps1` and the m05 comparison keep them equal to the catalog.

## Key rules
- One credential per user, hash only: `uq_user_credential_app_user_id`, `ck_user_credential_password_hash_format` (PHC argon2id/bcrypt).
- Role grants are effective-dated; the same role cannot overlap for the same user and scope: `ex_user_role_no_overlap`. Organisation-scoped roles must name an organisation: `trg_user_role_scope`.
- Blocking: exactly one target (`ck_block_list_single_target`), no self-block, one active block per pair (partial unique indexes); unblocking is a soft delete, so history is kept.
- Audit trail is append-only (trigger + revoked grants) and written through `audit.log_event()`, which takes the actor from the session and never from a parameter. Role, block, credential and consent changes are audited by triggers.
- Consent is append-only; withdrawal is a new row; `is_granted` defaults to false.
- Out of scope (docket Section 3): sub-roles inside an employer organisation. Extension: add permissions and org-scoped role grants; no table change.

## Entities
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| app_user | admin | Administration | Stub from Phase 1, extended here: Login identity (candidate, recruiter, consultant, admin, system). Stub in Phase 1; extended by Administration in M7-M10 | 1 | soft-delete | A |
| hash_algorithm | ref | Administration | Lookup: password hashing algorithm of a stored credential. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| consent_purpose | ref | Administration | Lookup: purpose a user gives or withdraws consent for. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| audit_action | ref | Administration | Lookup: sensitive action recorded in the audit trail. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| error_severity | ref | Administration | Lookup: severity of a logged system error. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| app_role | admin | Administration | Lookup: actor role (docket Section 3). Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| permission | admin | Administration | Lookup: action a role may perform. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| user_credential | admin | Administration | Password credential of a login identity: hash only, one per user (owned by app_user). Restricted grants in M18 | 1 | hard-delete | A |
| app_role_permission | admin | Administration | Permission granted to a role (junction, owned by both sides) | 1 | hard-delete | A |
| user_role | admin | Administration | Role held by a user, optionally scoped to an organisation, over an effective period; revocation closes the period (history kept) | 1 | hard-delete | A |
| consent_record | admin | Administration | Consent given or withdrawn; the latest row per user and purpose is the current state (withdrawal is a new row) | 1 | append-only | A |
| block_list | admin | Administration | A user (usually a candidate) blocks one user or one organisation; unblocking sets deleted_at so history is kept. RLS in M18 hides the blocker from the blocked party | 2 | soft-delete | A |
| audit_event | audit | Administration | Audit trail of sensitive actions (RG4); application users cannot update or delete it (trigger + revoked grants). Retention: 7 years | 1 | append-only | A |
| error_log | audit | Administration | System errors (application and integration). Retention: 90 days | 1 | append-only | A |

## Validation checklist (reviewer ticks)
- [ ] Every domain of this module in docket Section 7 has an entity.
- [ ] No two entities hold the same fact; stubs are extended, not duplicated.
- [ ] Every enumeration has a `ref` (or module) lookup.
- [ ] `python tools/reserved_words.py` passes on this file.
