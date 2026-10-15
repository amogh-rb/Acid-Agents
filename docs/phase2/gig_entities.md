# Gig marketplace: entities (M7) — owner C

Backlogs B26, B29, B32, B35. DDL: `ddl/50_gig.sql`. Tests: `tests/constraints/m10_gig.sql`. Relationships: `docs/phase2/gig_relationships.md`.

Entity rows were drafted from the DDL comments with `tools/draft_design_docs.py` and reviewed; `tests/docs/m07_phase2_docs.ps1` and the m05 comparison keep them equal to the catalog.

## Key rules
- Separate subsystem (00_decisions section 8). Gig worker profiles are separate from candidate profiles.
- Pricing: `ck_gig_request_pricing` (fixed price, or rate + unit, never both); windows `ck_gig_request_window` / `ck_gig_assignment_window`.
- B35: `ex_gig_assignment_worker_window` excludes overlapping windows for one worker while assignments are active or handed off; cancelled and completed ones do not block.
- Bids flow one way: workers apply; only the requester accepts or rejects; only the worker withdraws (`trg_gig_application_blacklist` also rejects blacklisted workers and closed gigs). Assignments need an accepted application (`trg_gig_assignment_accepted`) and match it via a composite FK.
- Fulfilment is external: `gig_fulfilment_handoff` holds the idempotency key and external reference; `gig_earning_reference` is append-only and `[integration-write]` (only talentra_integration inserts; the app reads; a replayed event is rejected by `uq_gig_earning_reference_source`).
- Ratings: 1-5, one per assignment, only for completed assignments and only by the requester (`trg_gig_rating_completed_assignment`).

## Entities
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| pricing_model | ref | Gig marketplace | Lookup: how a gig is priced. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| rate_unit | ref | Gig marketplace | Lookup: unit a gig rate is charged per. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| gig_request_status | ref | Gig marketplace | Lookup: gig request lifecycle. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| gig_application_status | ref | Gig marketplace | Lookup: state of a gig application. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| gig_assignment_status | ref | Gig marketplace | Lookup: state of a gig assignment. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| handoff_status | ref | Gig marketplace | Lookup: state of a handoff to the external fulfilment system. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| earning_kind | ref | Gig marketplace | Lookup: kind of earnings figure reported by the fulfilment system. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| worker_list_kind | ref | Gig marketplace | Lookup: requester list a gig worker is on. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| gig_worker_profile | gig | Gig marketplace | Gig worker profile, separate from candidate profiles (docket Section 2); 1:1 with app_user | 1 | soft-delete | C |
| gig_service_offering | gig | Gig marketplace | Service a gig worker offers, one per skill (owned by the worker profile) | 1 | hard-delete | C |
| gig_charge_rate | gig | Gig marketplace | Effective-dated charge rate of a service offering; one rate per unit at a time (owned by the offering) | 1 | hard-delete | C |
| gig_availability | gig | Gig marketplace | Time slot a gig worker is available; slots of one worker do not overlap (owned by the worker profile) | 1 | hard-delete | C |
| gig_request | gig | Gig marketplace | Short project-based request with a time window and a fixed or rate-based price | 1 | soft-delete | C |
| gig_application | gig | Gig marketplace | Gig worker applies to a gig request; bids flow one way and only the requester decides | 1 | hard-delete | C |
| gig_assignment | gig | Gig marketplace | Accepted gig application turned into work for a window; fulfilment itself runs in the external system | 1 | hard-delete | C |
| gig_fulfilment_handoff | gig | Gig marketplace | Handoff of an assignment to the external fulfilment system (integration boundary): idempotent send, external reference, status | 1 | hard-delete | C |
| gig_earning_reference | gig | Gig marketplace | Estimated, projected and total earnings reported by the fulfilment system (source of truth); a newer figure is a new row. The application can only read it | 1 | append-only | C |
| gig_requester_worker_list | gig | Gig marketplace | Requester favourite or blacklist entry for a worker; a worker is on at most one list per requester (owned by both sides) | 1 | hard-delete | C |
| gig_rating | gig | Gig marketplace | Requester rating of a completed gig, one per assignment | 1 | hard-delete | C |

## Validation checklist (reviewer ticks)
- [ ] Every domain of this module in docket Section 7 has an entity.
- [ ] No two entities hold the same fact; stubs are extended, not duplicated.
- [ ] Every enumeration has a `ref` (or module) lookup.
- [ ] `python tools/reserved_words.py` passes on this file.
