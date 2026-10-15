# Notifications, preferences and community: relationships (M16) — owner B

Same conventions as `docs/phase1/relationships.md`: actor FKs and lookup label keys are not repeated. Reasons come from the column comments in `ddl/80_notif.sql`.

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| community_post.author_app_user_id | admin.app_user | N:1 | no | RESTRICT | Author |
| community_post.post_body_language_id | ref.language | N:1 | yes | RESTRICT | NULL: not detected (RG7). Language of post_body |
| community_reaction.community_post_id | notif.community_post | N:1 | no | CASCADE | Owned child: Post |
| community_reaction.app_user_id | admin.app_user | N:1 | no | CASCADE | Owned child: Reacting user |
| community_reaction.reaction_type_code | ref.reaction_type | N:1 | no | RESTRICT | like, celebrate, insightful |
| delivery_provider_receipt.notification_channel_code | ref.notification_channel | N:1 | no | RESTRICT | Channel / provider family |
| delivery_provider_receipt.notification_delivery_id | notif.notification_delivery | N:1 | no | CASCADE | Owned child: Delivery the provider id belongs to (one per delivery); owned child of the delivery |
| delivery_provider_receipt.delivery_queued_at | notif.notification_delivery(queued_at) | N:1 | no | CASCADE | Owned child: Partition key of the delivery (half of the composite FK) |
| faq.question_label_key | ref.ui_label(label_key) | N:1 | no | RESTRICT | UI label key of the question |
| faq.answer_label_key | ref.ui_label(label_key) | N:1 | no | RESTRICT | UI label key of the answer |
| faq.ticket_category_code | ref.ticket_category | N:1 | no | RESTRICT | Topic, shared with support tickets |
| job_alert.candidate_profile_id | profile.candidate_profile | N:1 | no | CASCADE | Owned child: Candidate receiving the alert |
| job_alert.saved_search_id | job.saved_search | N:1 | no | CASCADE | Owned child: Saved search whose matches are sent |
| job_alert.alert_frequency_code | ref.alert_frequency | N:1 | no | RESTRICT | instant, daily, weekly; default daily |
| job_alert.notification_channel_code | ref.notification_channel | N:1 | no | RESTRICT | Channel; default email |
| notification.recipient_app_user_id | admin.app_user | N:1 | no | CASCADE | Owned child: Recipient |
| notification.notification_event_type_code | ref.notification_event_type | N:1 | no | RESTRICT | Triggering event |
| notification.message_label_key | ref.ui_label(label_key) | N:1 | no | RESTRICT | UI label key of the message template |
| notification_delivery.notification_id | notif.notification | N:1 | no | CASCADE | Owned child: Notification delivered |
| notification_delivery.notification_channel_code | ref.notification_channel | N:1 | no | RESTRICT | Channel |
| notification_delivery.delivery_status_code | ref.delivery_status | N:1 | no | RESTRICT | queued, sent, delivered, opened, failed, suppressed; default queued |
| notification_preference.app_user_id | admin.app_user | N:1 | no | CASCADE | Owned child: User |
| notification_preference.notification_event_type_code | ref.notification_event_type | N:1 | no | RESTRICT | Event type |
| notification_preference.notification_channel_code | ref.notification_channel | N:1 | no | RESTRICT | Channel |
| support_ticket.requester_app_user_id | admin.app_user | N:1 | no | RESTRICT | User who raised it |
| support_ticket.assignee_app_user_id | admin.app_user | N:1 | yes | RESTRICT | NULL: not yet assigned. Support agent |
| support_ticket.ticket_category_code | ref.ticket_category | N:1 | no | RESTRICT | Category |
| support_ticket.ticket_status_code | ref.ticket_status | N:1 | no | RESTRICT | open, in_progress, resolved, closed; default open |
| support_ticket_message.support_ticket_id | notif.support_ticket | N:1 | no | CASCADE | Owned child: Ticket |
| support_ticket_message.author_app_user_id | admin.app_user | N:1 | no | RESTRICT | Requester or agent |
| support_ticket_message.message_body_language_id | ref.language | N:1 | yes | RESTRICT | NULL: not detected (RG7). Language of message_body |
| user_preference.app_user_id | admin.app_user | N:1 | no | CASCADE | Owned child: User (one row per user) |
| user_preference.ui_language_id | ref.language | N:1 | no | RESTRICT | UI language; ref.ui_text falls back to the default language when a label is untranslated |
| user_preference.timezone_id | ref.timezone | N:1 | yes | RESTRICT | NULL: use the city or browser time zone. Display time zone |
| user_preference.profile_visibility_code | ref.profile_visibility | N:1 | no | RESTRICT | Privacy: who may find the profile; default all_employers |

## Validation checklist (reviewer ticks)
- [ ] RESTRICT by default; every CASCADE is an owned child.
- [ ] Every optional relationship states what NULL means.
