# Notifications, preferences and community: entities (M15) — owner B

Backlogs B48, B51, B54, B57. DDL: `ddl/80_notif.sql`. Tests: `tests/constraints/m18_notif.sql`. Relationships: `docs/phase4/notif_relationships.md`.

Rows were drafted from the DDL comments with `tools/draft_design_docs.py` and reviewed. The m05 comparison keeps them equal to the catalog.

## Key rules
- Preferences: `user_preference` (UI language, which must be UI-supported via `trg_user_preference_ui_language`; time zone; privacy: profile visibility, salary disclosure, recruiter contact), `notification_preference` (per event and channel), `job_alert` (on a saved search, frequency, channel).
- Notifications store a translatable message key + parameters, never bodies (docket Section 6).
- B57 high-volume write path: `notification_delivery` is RANGE-partitioned monthly on `queued_at` (`_pYYYYMM` + `_default`, created ahead by `notif.ensure_delivery_partitions`). Retention detaches and drops old months.
- Provider idempotency: `delivery_provider_receipt` holds the globally unique provider message id. A unique key on the partitioned table would have to include the partition key and so could not be global.
- Community posts/reactions, FAQs (question and answer are UI labels, so they are translated) and support tickets are modelled thinly (Tier 2).

## Entities
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| notification_channel | ref | Notifications, preferences and community | Lookup: channel a notification is delivered on. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| notification_event_type | ref | Notifications, preferences and community | Lookup: event that triggers a notification. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| delivery_status | ref | Notifications, preferences and community | Lookup: delivery state of a notification on one channel. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| alert_frequency | ref | Notifications, preferences and community | Lookup: how often a job alert is sent. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| profile_visibility | ref | Notifications, preferences and community | Lookup: who may find a candidate profile. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| reaction_type | ref | Notifications, preferences and community | Lookup: reaction to a community post. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| ticket_category | ref | Notifications, preferences and community | Lookup: support ticket category. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| ticket_status | ref | Notifications, preferences and community | Lookup: support ticket status. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | B |
| user_preference | notif | Notifications, preferences and community | Language preference and privacy settings of a user (owned by app_user); a missing row means the defaults (default language, all employers) | 1 | hard-delete | B |
| notification_preference | notif | Notifications, preferences and community | Per-event, per-channel notification switch (owned by app_user); a missing row means enabled | 1 | hard-delete | B |
| job_alert | notif | Notifications, preferences and community | Job alert preference: send matches of a saved search at a frequency on a channel (owned by the candidate) | 1 | hard-delete | B |
| notification | notif | Notifications, preferences and community | Notification for a user: a translatable message key plus parameters, rendered per language at send time; no message bodies stored (owned by app_user). Retention: 180 days | 1 | hard-delete | B |
| notification_delivery | notif | Notifications, preferences and community | Delivery of a notification on one channel and its status (high-volume write path). Monthly RANGE partitions on queued_at; retention = detach and drop months older than 13 months | 1 | hard-delete | B |
| delivery_provider_receipt | notif | Notifications, preferences and community | Provider message id assigned to a delivery; globally unique per channel, so a duplicate provider callback is rejected (idempotency). Dropped with its delivery partition | 1 | hard-delete | B |
| community_post | notif | Notifications, preferences and community | Community post by a user (moderation removes by soft delete) | 1 | soft-delete | B |
| community_reaction | notif | Notifications, preferences and community | One user reaction to a post (owned by the post); one per user per post | 1 | hard-delete | B |
| faq | notif | Notifications, preferences and community | FAQ entry; question and answer are UI labels, so they are translated like any other UI text (RG7) | 1 | hard-delete | B |
| support_ticket | notif | Notifications, preferences and community | Support ticket raised by a user. Retention: 2 years after resolution | 1 | hard-delete | B |
| support_ticket_message | notif | Notifications, preferences and community | Message in a support ticket thread (owned by the ticket; purged with it; never edited by the application) | 1 | hard-delete | B |

## Validation checklist (reviewer ticks)
- [ ] Every domain of this module in docket Section 7 has an entity.
- [ ] No two entities hold the same fact.
- [ ] Every enumeration has a lookup.
