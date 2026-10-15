# Gig marketplace: relationships (M8) — owner C

Same conventions as `docs/phase1/relationships.md` (actor FKs and lookup label keys are not repeated; FKs already documented in Phase 1 are not repeated). Reasons come from the column comments in `ddl/50_gig.sql`.

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| gig_application.gig_request_id | gig.gig_request | N:1 | no | RESTRICT | Gig applied to |
| gig_application.gig_worker_profile_id | gig.gig_worker_profile | N:1 | no | RESTRICT | Applying worker |
| gig_application.gig_application_status_code | ref.gig_application_status | N:1 | no | RESTRICT | applied, accepted, rejected, withdrawn; default applied |
| gig_application.proposed_currency_code | ref.currency | N:1 | yes | RESTRICT | NULL: no counter-price. Currency of proposed_amount |
| gig_assignment.gig_application_id | gig.gig_application | 1:1 | no | RESTRICT | Accepted application (unique) |
| gig_assignment.gig_request_id | gig.gig_request | N:1 | no | RESTRICT | Gig (copied from the application, checked by the composite FK) |
| gig_assignment.gig_worker_profile_id | gig.gig_worker_profile | N:1 | no | RESTRICT | Worker (copied from the application for the overlap rule) |
| gig_assignment.gig_assignment_status_code | ref.gig_assignment_status | N:1 | no | RESTRICT | active, handed_off, completed, cancelled; default active |
| gig_availability.gig_worker_profile_id | gig.gig_worker_profile | N:1 | no | CASCADE | Owned child: Owning worker |
| gig_charge_rate.gig_service_offering_id | gig.gig_service_offering | N:1 | no | CASCADE | Owned child: Owning offering |
| gig_charge_rate.rate_unit_code | ref.rate_unit | N:1 | no | RESTRICT | hour, day, task |
| gig_charge_rate.rate_currency_code | ref.currency | N:1 | no | RESTRICT | Currency of rate_amount |
| gig_earning_reference.gig_assignment_id | gig.gig_assignment | N:1 | no | RESTRICT | Assignment the figure is for |
| gig_earning_reference.earning_kind_code | ref.earning_kind | N:1 | no | RESTRICT | estimated, projected, total |
| gig_earning_reference.currency_code | ref.currency | N:1 | no | RESTRICT | Currency of earning_amount |
| gig_fulfilment_handoff.gig_assignment_id | gig.gig_assignment | N:1 | no | RESTRICT | Assignment handed off (one handoff per assignment) |
| gig_fulfilment_handoff.handoff_status_code | ref.handoff_status | N:1 | no | RESTRICT | pending, sent, acknowledged, failed; default pending |
| gig_rating.gig_assignment_id | gig.gig_assignment | 1:1 | no | RESTRICT | Completed assignment rated (unique) |
| gig_rating.review_language_id | ref.language | N:1 | yes | RESTRICT | NULL: no review or not detected. Language of review_text |
| gig_request.requester_app_user_id | admin.app_user | N:1 | no | RESTRICT | User who posted the gig and alone decides on applications |
| gig_request.requester_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: individual requester. Organisation the requester posts for |
| gig_request.gig_description_language_id | ref.language | N:1 | yes | RESTRICT | NULL: not detected (RG7). Language of the description |
| gig_request.skill_id | ref.skill | N:1 | no | RESTRICT | Primary skill required |
| gig_request.city_id | ref.city | N:1 | yes | RESTRICT | NULL: remote gig. Where the work happens |
| gig_request.pricing_model_code | ref.pricing_model | N:1 | no | RESTRICT | fixed or rate |
| gig_request.rate_unit_code | ref.rate_unit | N:1 | yes | RESTRICT | NULL: fixed-price gig (CHECK). Unit of rate_amount |
| gig_request.currency_code | ref.currency | N:1 | no | RESTRICT | Currency of the price |
| gig_request.gig_request_status_code | ref.gig_request_status | N:1 | no | RESTRICT | Lifecycle; default draft |
| gig_requester_worker_list.requester_app_user_id | admin.app_user | N:1 | no | CASCADE | Owned child: Requester maintaining the list |
| gig_requester_worker_list.gig_worker_profile_id | gig.gig_worker_profile | N:1 | no | CASCADE | Owned child: Worker listed |
| gig_requester_worker_list.worker_list_kind_code | ref.worker_list_kind | N:1 | no | RESTRICT | favourite or blacklist |
| gig_service_offering.gig_worker_profile_id | gig.gig_worker_profile | N:1 | no | CASCADE | Owned child: Owning worker |
| gig_service_offering.skill_id | ref.skill | N:1 | no | RESTRICT | Skill offered |
| gig_worker_profile.app_user_id | admin.app_user | 1:1 | no | RESTRICT | Login identity (unique) |
| gig_worker_profile.bio_language_id | ref.language | N:1 | yes | RESTRICT | NULL: no bio or not detected (RG7). Language of bio |
| gig_worker_profile.base_city_id | ref.city | N:1 | yes | RESTRICT | NULL: remote-only worker. City the worker is based in |

## Validation checklist (reviewer ticks)
- [ ] RESTRICT by default; every CASCADE is an owned child.
- [ ] Every optional relationship states what NULL means.
- [ ] Composite FKs prove cross-row consistency where a child copies a parent's keys.
