# Organisation and account: relationships (M8) — owner B

Same conventions as `docs/phase1/relationships.md` (actor FKs and lookup label keys are not repeated; FKs already documented in Phase 1 are not repeated). Reasons come from the column comments in `ddl/45_org.sql`.

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| account.account_status_code | ref.account_status | N:1 | no | RESTRICT | trial, active, suspended, closed; default trial |
| account_administrator.account_id | org.account | N:1 | no | CASCADE | Owned child: Account administered |
| account_administrator.app_user_id | admin.app_user | N:1 | no | RESTRICT | Administrator |
| organisation.organisation_type_code | ref.organisation_type | N:1 | no | RESTRICT | employer, client, staffing_agency, consultancy, campus; default employer |
| organisation.account_id | org.account | N:1 | yes | RESTRICT | NULL: not a paying customer (a client of an agency, or a past employer named on profiles). Commercial account |
| organisation.parent_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: top of its hierarchy. Parent in the organisation hierarchy (group > subsidiary > division) |
| organisation.industry_id | ref.industry | N:1 | yes | RESTRICT | NULL: not provided. Primary industry |
| organisation.employee_count_band_code | ref.employee_count_band | N:1 | yes | RESTRICT | NULL: not provided. Company size band |
| organisation.verification_status_code | ref.verification_status | N:1 | no | RESTRICT | Overall verification outcome (company and tax registration); default pending |
| organisation_identifier.organisation_id | org.organisation | N:1 | no | CASCADE | Owned child: Owning organisation |
| organisation_identifier.identifier_type_code | ref.identifier_type | N:1 | no | RESTRICT | Identifier type; its regex and applies_to_organisation are enforced by org.add_identifier |
| organisation_identifier.verification_status_code | ref.verification_status | N:1 | no | RESTRICT | Outcome of the tax/registration lookup; default pending |
| organisation_location.organisation_id | org.organisation | N:1 | no | CASCADE | Owned child: Owning organisation |
| organisation_location.city_id | ref.city | N:1 | no | RESTRICT | City (implies state and country) |
| recruiter_mapping.app_user_id | admin.app_user | N:1 | no | RESTRICT | Recruiter |
| recruiter_mapping.organisation_id | org.organisation | N:1 | no | RESTRICT | Organisation the recruiter acts for (RLS key in M18) |
| verification.organisation_id | org.organisation | N:1 | no | RESTRICT | Organisation being verified |
| verification.verification_kind_code | ref.verification_kind | N:1 | no | RESTRICT | company_registration, tax_registration, address |
| verification.organisation_identifier_id | org.organisation_identifier | N:1 | yes | RESTRICT | NULL: address verification needs no identifier. Identifier used for the lookup |
| verification.verification_status_code | ref.verification_status | N:1 | no | RESTRICT | pending until the provider answers; default pending |

## Validation checklist (reviewer ticks)
- [ ] RESTRICT by default; every CASCADE is an owned child.
- [ ] Every optional relationship states what NULL means.
- [ ] Composite FKs prove cross-row consistency where a child copies a parent's keys.
