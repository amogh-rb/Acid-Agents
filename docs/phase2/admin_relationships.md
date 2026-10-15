# Administration: relationships (M8) — owner A

Same conventions as `docs/phase1/relationships.md` (actor FKs and lookup label keys are not repeated; FKs already documented in Phase 1 are not repeated). Reasons come from the column comments in `ddl/40_admin.sql`.

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| app_role_permission.app_role_code | admin.app_role | N:1 | no | CASCADE | Owned child: Role |
| app_role_permission.permission_code | admin.permission | N:1 | no | CASCADE | Owned child: Permission held by the role |
| app_user.login_phone_country_id | ref.country | N:1 | yes | RESTRICT | NULL: no login phone. Country of login_phone |
| block_list.blocker_app_user_id | admin.app_user | N:1 | no | RESTRICT | User who blocked |
| block_list.blocked_app_user_id | admin.app_user | N:1 | yes | RESTRICT | NULL: an organisation is blocked instead. Blocked recruiter, consultant or employer user |
| block_list.blocked_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: a single user is blocked instead. Blocked company |
| consent_record.app_user_id | admin.app_user | N:1 | no | RESTRICT | User giving or withdrawing consent |
| consent_record.consent_purpose_code | ref.consent_purpose | N:1 | no | RESTRICT | Purpose |
| user_credential.app_user_id | admin.app_user | 1:1 | no | CASCADE | Owned child: Owner (unique: one credential per user) |
| user_credential.hash_algorithm_code | ref.hash_algorithm | N:1 | no | RESTRICT | Algorithm of password_hash; default argon2id |
| user_role.app_user_id | admin.app_user | N:1 | no | RESTRICT | User holding the role |
| user_role.app_role_code | admin.app_role | N:1 | no | RESTRICT | Role held |
| user_role.organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: platform-wide role (candidate, admin). Organisation the role applies to |
| audit_event.actor_app_user_id | admin.app_user | N:1 | yes | RESTRICT | NULL: unauthenticated actor (failed login with an unknown identifier). User who acted |
| audit_event.audit_action_code | ref.audit_action | N:1 | no | RESTRICT | Action performed |
| error_log.error_severity_code | ref.error_severity | N:1 | no | RESTRICT | warning, error, critical |
| error_log.app_user_id | admin.app_user | N:1 | yes | RESTRICT | NULL: background job or anonymous request. User whose request failed |

## Validation checklist (reviewer ticks)
- [ ] RESTRICT by default; every CASCADE is an owned child.
- [ ] Every optional relationship states what NULL means.
- [ ] Composite FKs prove cross-row consistency where a child copies a parent's keys.
