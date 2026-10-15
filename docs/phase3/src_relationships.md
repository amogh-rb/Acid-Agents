# Sourcing and consultant requests: relationships (M12) — owner B

Same conventions as `docs/phase1/relationships.md`: actor FKs and lookup label keys are not repeated, and FKs already documented in Phase 1 are not repeated. Reasons come from the column comments in `ddl/65_src.sql`.

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| outreach_batch.sender_app_user_id | admin.app_user | N:1 | no | RESTRICT | User sending the outreach |
| outreach_batch.sender_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: freelance consultant. Organisation the sender acts for |
| outreach_batch.job_requirement_id | job.job_requirement | N:1 | yes | RESTRICT | NULL: general talent-pool outreach. Job the outreach is about |
| outreach_batch.sourcing_request_id | src.sourcing_request | N:1 | yes | RESTRICT | NULL: employer outreach, not a consultant engagement. Sourcing request it belongs to |
| outreach_batch.outreach_channel_code | ref.outreach_channel | N:1 | no | RESTRICT | email, sms, whatsapp, in_app |
| outreach_recipient.outreach_batch_id | src.outreach_batch | N:1 | no | CASCADE | Owned child: Batch |
| outreach_recipient.candidate_profile_id | profile.candidate_profile | N:1 | no | RESTRICT | Candidate contacted (an existing profile; recruiters cannot register candidates) |
| outreach_recipient.outreach_recipient_status_code | ref.outreach_recipient_status | N:1 | no | RESTRICT | queued, sent, delivered, failed, replied, opted_out; default queued |
| sourcing_request.job_requirement_id | job.job_requirement | N:1 | no | RESTRICT | Job to source for (must be open to consultants) |
| sourcing_request.consultant_app_user_id | admin.app_user | N:1 | no | RESTRICT | Requesting consultant (must hold the consultant role) |
| sourcing_request.consultant_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: freelance consultant. Consultancy the consultant works for |
| sourcing_request.sourcing_request_status_code | ref.sourcing_request_status | N:1 | no | RESTRICT | requested, accepted, declined, withdrawn, closed; default requested |
| sourcing_request.decided_by_app_user_id | admin.app_user | N:1 | yes | RESTRICT | NULL: not decided yet. Employer user who accepted or declined |
| sourcing_shortlist.sourcing_request_id | src.sourcing_request | N:1 | no | CASCADE | Owned child: Sourcing request |
| sourcing_shortlist.shortlist_id | job.shortlist | N:1 | no | RESTRICT | Shortlist in the Jobs module |
| sourcing_shortlist.job_requirement_id | job.job_requirement | N:1 | no | RESTRICT | Job of both the request and the shortlist (checked by two composite FKs) |

## Validation checklist (reviewer ticks)
- [ ] RESTRICT by default; every CASCADE is an owned child.
- [ ] Every optional relationship states what NULL means.
- [ ] Composite FKs prove cross-row consistency where a child copies a parent's keys.
