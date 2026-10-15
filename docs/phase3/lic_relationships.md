# Licences, seats, devices and sessions: relationships (M12) — owner A

Same conventions as `docs/phase1/relationships.md`: actor FKs and lookup label keys are not repeated, and FKs already documented in Phase 1 are not repeated. Reasons come from the column comments in `ddl/60_lic.sql`.

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| licence.account_id | org.account | N:1 | no | RESTRICT | Licensed account |
| licence.licence_status_code | ref.licence_status | N:1 | no | RESTRICT | active, suspended, expired; default active |
| licence_seat.licence_id | lic.licence | N:1 | no | RESTRICT | Licence the seat belongs to |
| licence_seat.app_user_id | admin.app_user | N:1 | no | RESTRICT | User holding the seat (one active seat per user) |
| login_attempt.app_user_id | admin.app_user | N:1 | yes | RESTRICT | NULL: identifier did not match any account. User who tried to log in |
| login_attempt.registered_device_id | lic.registered_device | N:1 | yes | RESTRICT | NULL: rejected before the device was registered (unknown user, bad credentials). Device used |
| login_attempt.login_outcome_code | ref.login_outcome | N:1 | no | RESTRICT | started, device_limit, no_seat, licence_inactive, device_revoked, bad_credentials, locked |
| login_session.app_user_id | admin.app_user | N:1 | no | RESTRICT | Session owner |
| login_session.registered_device_id | lic.registered_device | N:1 | no | RESTRICT | Device used (must belong to the user) |
| login_session.licence_seat_id | lic.licence_seat | N:1 | no | RESTRICT | Seat the session counts against (must belong to the user) |
| login_session.session_end_reason_code | ref.session_end_reason | N:1 | yes | RESTRICT | NULL: still open. logout, revoked, device_revoked, idle_timeout, expired |
| registered_device.app_user_id | admin.app_user | N:1 | no | CASCADE | Owned child: Device owner |
| registered_device.device_platform_code | ref.device_platform | N:1 | no | RESTRICT | web, android, ios, desktop; default web |
| session_revocation.login_session_id | lic.login_session | N:1 | no | RESTRICT | Session revoked (once) |

## Validation checklist (reviewer ticks)
- [ ] RESTRICT by default; every CASCADE is an owned child.
- [ ] Every optional relationship states what NULL means.
- [ ] Composite FKs prove cross-row consistency where a child copies a parent's keys.
