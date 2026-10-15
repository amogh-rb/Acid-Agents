# Sourcing and consultant requests: entities (M11) — owner B

Backlogs B37, B40, B43, B46. DDL: `ddl/65_src.sql`. Tests: `tests/constraints/m14_src.sql`. Relationships: `docs/phase3/src_relationships.md`.

Rows were drafted from the DDL comments with `tools/draft_design_docs.py` and reviewed. The m05 comparison keeps them equal to the catalog.

## Key rules
- B46: `trg_sourcing_request_consultant_open`. The job must be open to consultants, the requester must hold the consultant role, and only an employer or recruiter of the job's organisation decides.
- Decision columns agree with the status (`ck_sourcing_request_decision`); a decline needs a reason (`ck_sourcing_request_decline_reason`); one live request per consultant per job.
- Candidate shortlists reuse `job.shortlist`; two composite FKs prove the request and the shortlist are for the same job.
- Bulk outreach: unique batch idempotency key, one recipient row per candidate per batch, unique provider message reference; `trg_outreach_recipient_not_blocked` rejects candidates who blocked the sender user or organisation. Only a template key is stored, never message bodies.
- Recruiters contact existing candidates only; they cannot register candidates (docket Section 3).

## Entities
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| sourcing_request_status | ref | Sourcing and consultant requests | Lookup: state of a consultant sourcing request. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| outreach_channel | ref | Sourcing and consultant requests | Lookup: channel of a bulk outreach. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| outreach_recipient_status | ref | Sourcing and consultant requests | Lookup: delivery state of one outreach recipient. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| sourcing_request | src | Sourcing and consultant requests | Consultant request to source candidates for a job; the employer accepts or declines | 1 | hard-delete | B |
| sourcing_shortlist | src | Sourcing and consultant requests | Links a sourcing request to the job shortlist the consultant fills (owned by the request); the shortlist itself lives in job.shortlist | 1 | hard-delete | B |
| outreach_batch | src | Sourcing and consultant requests | Bulk outreach by a recruiter, employer or consultant to existing candidates. Message bodies are not stored (template key only; docket Section 6) | 1 | hard-delete | B |
| outreach_recipient | src | Sourcing and consultant requests | One candidate in an outreach batch and the delivery state (owned by the batch) | 1 | hard-delete | B |

## Validation checklist (reviewer ticks)
- [ ] Every domain of this module in docket Section 7 has an entity.
- [ ] No two entities hold the same fact; earlier-phase tables are extended, not duplicated.
- [ ] Every enumeration has a lookup.
