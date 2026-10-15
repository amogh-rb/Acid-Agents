# Licences, seats, devices and sessions: entities (M11) — owner A

Backlogs B36, B39, B42, B45. DDL: `ddl/60_lic.sql`. Tests: `tests/constraints/m14_lic.sql, tests/concurrency/m14_device_limit.ps1`. Relationships: `docs/phase3/lic_relationships.md`.

Rows were drafted from the DDL comments with `tools/draft_design_docs.py` and reviewed. The m05 comparison keeps them equal to the catalog.

## Key rules
- RG9: `ck_licence_max_users_positive`, `ck_licence_max_devices_per_user_positive` (both explicit columns, positive).
- Seats: one active seat per user (`uq_licence_seat_active_user`); active seats per licence <= max_users via `trg_licence_seat_limit`, which locks the licence row.
- Device limit at login (B45): `app.start_session` locks the user's seat row `FOR UPDATE`, counts sessions with `ended_at IS NULL AND expires_at > now()` (partial index `idx_login_session_active_user`), and either starts the session or records `login_attempt` + audit `device_limit_exceeded` and returns a rejection (so the audit row commits).
- Release: `app.end_session` (logout), `app.revoke_session` and `app.revoke_device` (both audited), `app.expire_idle_sessions` (idle timeout or hard expiry). Expired or revoked sessions never count.
- A session's device and seat must belong to its user (composite FKs). Session tokens and device fingerprints are stored only as SHA-256 hashes.
- Session tables are `[api-write]`: the application role cannot bypass the session API.

## Entities
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| licence_status | ref | Licences, seats, devices and sessions | Lookup: licence status. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| device_platform | ref | Licences, seats, devices and sessions | Lookup: platform of a registered device. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| session_end_reason | ref | Licences, seats, devices and sessions | Lookup: why a session ended. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| login_outcome | ref | Licences, seats, devices and sessions | Lookup: outcome of a login attempt. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | A |
| licence | lic | Licences, seats, devices and sessions | Subscription licence of an account: users allowed and devices allowed per user (RG9). Limits are copied from the plan when a subscription starts and may be raised per licence | 1 | hard-delete | A |
| licence_seat | lic | Licences, seats, devices and sessions | Seat of a licence allocated to a user; releasing sets released_at (history kept). Active seats per licence <= max_users (trg_licence_seat_limit) | 1 | hard-delete | A |
| registered_device | lic | Licences, seats, devices and sessions | Device a user has logged in from (owned by app_user); revoking sets revoked_at and ends its sessions (audited) | 1 | hard-delete | A |
| login_session | lic | Licences, seats, devices and sessions | Login session on a device under a licence seat (RG9: device, start, last activity, end). Active = ended_at IS NULL AND expires_at > now(). Retention: 90 days after end | 1 | hard-delete | A |
| login_attempt | lic | Licences, seats, devices and sessions | Login history: every attempt and its outcome, including device-limit rejections. Retention: 1 year | 1 | append-only | A |
| session_revocation | lic | Licences, seats, devices and sessions | Revocation of a session by an admin or the user (who = created_by); also written to the audit trail | 1 | append-only | A |

## Validation checklist (reviewer ticks)
- [ ] Every domain of this module in docket Section 7 has an entity.
- [ ] No two entities hold the same fact; earlier-phase tables are extended, not duplicated.
- [ ] Every enumeration has a lookup.
