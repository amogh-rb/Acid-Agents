# Analytics layer and reporting marts: entities (M15) — owner C

Backlogs B49, B52, B55, B58. DDL: `ddl/90_dw.sql`. Tests: `tests/constraints/m18_dw.sql`. Relationships: `docs/phase4/dw_relationships.md`.

Rows were drafted from the DDL comments with `tools/draft_design_docs.py` and reviewed. The m05 comparison keeps them equal to the catalog.

## Key rules
- Star schema: `dim_date`, `dim_organisation` (SCD1), `dim_candidate` and `dim_job_requirement` (SCD2: `valid_from`/`valid_to`/`is_current`, one current row per natural key, change detected by `row_hash`), `fact_application` (grain = application, from both the job pipeline and the gig subsystem), `agg_daily_funnel`, `etl_watermark`.
- Facts join the dimension version valid at `applied_at`, so history is reported as it was.
- `dw.refresh_marts()` is idempotent: hash-compared SCD2, upserted facts that change only when the source changed, and a recomputed aggregate. Running it twice changes nothing.
- KPIs (docket Section 8 was not issued): funnel conversion by stage, time to hire, volume by category; `dw.v_funnel_by_category` is the reporting view.
- Warehouse tables are `[derived]`: no audit columns (D6), read-only for the application; natural keys carry `nofk` so the warehouse survives operational purges. No names or contact details are copied.

## Entities
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| dim_date | dw | Analytics layer and reporting marts | Calendar dimension, one row per day 2024-2028 | 1 | derived | C |
| dim_organisation | dw | Analytics layer and reporting marts | Organisation dimension, SCD type 1 (attributes overwritten in place) | 1 | derived | C |
| dim_candidate | dw | Analytics layer and reporting marts | Candidate dimension, SCD type 2: one version per change of city, experience band or highest qualification. No direct identifiers (name, contact) are copied to the warehouse | 1 | derived | C |
| dim_job_requirement | dw | Analytics layer and reporting marts | Job requirement dimension, SCD type 2 on category, role, salary band and owner | 1 | derived | C |
| fact_application | dw | Analytics layer and reporting marts | One row per application from the job pipeline and the gig subsystem (single pipeline view); grain = application | 1 | derived | C |
| agg_daily_funnel | dw | Analytics layer and reporting marts | Daily hiring funnel per job category (applied, shortlisted, interviewed, offered, joined, time to hire), recomputed from fact_application | 1 | derived | C |
| etl_watermark | dw | Analytics layer and reporting marts | Bookkeeping of each refresh process: when it last ran and how much changed | 1 | derived | C |

## Validation checklist (reviewer ticks)
- [ ] Every domain of this module in docket Section 7 has an entity.
- [ ] No two entities hold the same fact.
- [ ] Every enumeration has a lookup.
