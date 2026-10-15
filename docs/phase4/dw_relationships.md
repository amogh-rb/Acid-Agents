# Analytics layer and reporting marts: relationships (M16) — owner C

Same conventions as `docs/phase1/relationships.md`: actor FKs and lookup label keys are not repeated. Reasons come from the column comments in `ddl/90_dw.sql`.

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| agg_daily_funnel.dim_date_id | dw.dim_date | N:1 | no | RESTRICT | Application date |
| dim_job_requirement.dim_organisation_id | dw.dim_organisation | N:1 | no | RESTRICT | Owning organisation |
| fact_application.dim_candidate_id | dw.dim_candidate | N:1 | yes | RESTRICT | NULL: gig application (gig workers are not candidates). Candidate version valid when applying |
| fact_application.dim_job_requirement_id | dw.dim_job_requirement | N:1 | yes | RESTRICT | NULL: gig application. Job version valid when applying |
| fact_application.dim_organisation_id | dw.dim_organisation | N:1 | yes | RESTRICT | NULL: gig posted by an individual requester. Hiring organisation |
| fact_application.applied_dim_date_id | dw.dim_date | N:1 | no | RESTRICT | Application date |

## Validation checklist (reviewer ticks)
- [ ] RESTRICT by default; every CASCADE is an owned child.
- [ ] Every optional relationship states what NULL means.
