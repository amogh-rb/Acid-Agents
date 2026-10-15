# Subscriptions, wallet, payments and download history: relationships (M12) — owner C

Same conventions as `docs/phase1/relationships.md`: actor FKs and lookup label keys are not repeated, and FKs already documented in Phase 1 are not repeated. Reasons come from the column comments in `ddl/70_billing.sql`.

| child.column | parent | cardinality | optional? | ON DELETE | reason |
|---|---|---|---|---|---|
| credit_consumption.wallet_ledger_entry_id | billing.wallet_ledger_entry | N:1 | no | RESTRICT | Ledger debit (one consumption per debit) |
| credit_consumption.consumption_purpose_code | ref.consumption_purpose | N:1 | no | RESTRICT | job_posting, profile_download, profile_view, outreach_message |
| credit_consumption.job_requirement_id | job.job_requirement | N:1 | yes | RESTRICT | NULL: purpose is not a job posting. Job posted |
| credit_consumption.outreach_batch_id | src.outreach_batch | N:1 | yes | RESTRICT | NULL: purpose is not outreach. Outreach batch sent |
| invoice.account_id | org.account | N:1 | no | RESTRICT | Invoiced account |
| invoice.payment_order_id | billing.payment_order | N:1 | no | RESTRICT | Order invoiced (one invoice per order) |
| invoice.invoice_status_code | ref.invoice_status | N:1 | no | RESTRICT | issued, paid, void; default issued |
| invoice.currency_code | ref.currency | N:1 | no | RESTRICT | Currency of all amounts |
| payment_event.payment_order_id | billing.payment_order | N:1 | no | RESTRICT | Order the event is about |
| payment_event.payment_gateway_code | ref.payment_gateway | N:1 | no | RESTRICT | Gateway that sent the event |
| payment_event.payment_status_code | ref.payment_status | N:1 | no | RESTRICT | Order status the event reports |
| payment_event.event_currency_code | ref.currency | N:1 | yes | RESTRICT | NULL: no amount in the event. Currency of event_amount |
| payment_order.account_id | org.account | N:1 | no | RESTRICT | Paying account |
| payment_order.subscription_id | billing.subscription | N:1 | yes | RESTRICT | NULL: wallet recharge. Subscription paid for |
| payment_order.wallet_id | billing.wallet | N:1 | yes | RESTRICT | NULL: subscription payment. Wallet recharged |
| payment_order.order_currency_code | ref.currency | N:1 | no | RESTRICT | Currency of order_amount |
| payment_order.payment_gateway_code | ref.payment_gateway | N:1 | no | RESTRICT | razorpay, stripe |
| payment_order.payment_status_code | ref.payment_status | N:1 | no | RESTRICT | created, authorised, captured, failed, partially_refunded, refunded; default created |
| plan.billing_cycle_code | ref.billing_cycle | N:1 | no | RESTRICT | monthly, quarterly, annual |
| plan.price_currency_code | ref.currency | N:1 | no | RESTRICT | Currency of price_amount |
| plan_entitlement.plan_id | billing.plan | N:1 | no | CASCADE | Owned child: Owning plan |
| plan_entitlement.entitlement_type_code | ref.entitlement_type | N:1 | no | RESTRICT | Entitlement |
| profile_download_event.candidate_profile_id | profile.candidate_profile | N:1 | no | RESTRICT | Profile downloaded (subject) |
| profile_download_event.downloader_app_user_id | admin.app_user | N:1 | no | RESTRICT | User who downloaded (actor) |
| profile_download_event.downloader_organisation_id | org.organisation | N:1 | yes | RESTRICT | NULL: independent consultant. Organisation the downloader acted for |
| profile_download_event.wallet_ledger_entry_id | billing.wallet_ledger_entry | N:1 | no | RESTRICT | Ledger debit for this download (required; one download per debit) |
| refund.payment_order_id | billing.payment_order | N:1 | no | RESTRICT | Payment refunded |
| refund.refund_currency_code | ref.currency | N:1 | no | RESTRICT | Must equal the order currency |
| refund.refund_status_code | ref.refund_status | N:1 | no | RESTRICT | requested, processed, failed; default requested |
| subscription.licence_id | lic.licence | N:1 | no | RESTRICT | Licence the subscription funds |
| subscription.plan_id | billing.plan | N:1 | no | RESTRICT | Plan bought |
| subscription.subscription_status_code | ref.subscription_status | N:1 | no | RESTRICT | pending_payment, active, expired, cancelled; default pending_payment |
| subscription.price_currency_code | ref.currency | N:1 | no | RESTRICT | Currency of price_amount |
| subscription_cancellation.subscription_id | billing.subscription | N:1 | no | RESTRICT | Subscription cancelled (once) |
| subscription_renewal.from_subscription_id | billing.subscription | N:1 | no | RESTRICT | Subscription being renewed |
| subscription_renewal.to_subscription_id | billing.subscription | N:1 | no | RESTRICT | New subscription |
| wallet.account_id | org.account | N:1 | no | RESTRICT | Owning account |
| wallet.currency_code | ref.currency | N:1 | no | RESTRICT | Wallet currency |
| wallet_ledger_entry.wallet_id | billing.wallet | N:1 | no | RESTRICT | Wallet |
| wallet_ledger_entry.ledger_entry_type_code | ref.ledger_entry_type | N:1 | no | RESTRICT | recharge, consumption, refund, grant, correction |
| wallet_ledger_entry.currency_code | ref.currency | N:1 | no | RESTRICT | Currency of amount and balance_after (the wallet currency) |
| wallet_ledger_entry.reverses_wallet_ledger_entry_id | billing.wallet_ledger_entry | N:1 | yes | RESTRICT | NULL: not a correction. Entry this correction reverses (each entry reversed at most once) |
| wallet_ledger_entry.payment_order_id | billing.payment_order | N:1 | yes | RESTRICT | NULL: not a recharge. Payment that funded a recharge |
| wallet_ledger_entry.refund_id | billing.refund | N:1 | yes | RESTRICT | NULL: not a refund. Refund that debited the wallet |
| profile_view_event.wallet_ledger_entry_id | billing.wallet_ledger_entry | N:1 | yes | RESTRICT | NULL: free view (plan entitlement or own applicant). Ledger debit when the view was paid |

## Validation checklist (reviewer ticks)
- [ ] RESTRICT by default; every CASCADE is an owned child.
- [ ] Every optional relationship states what NULL means.
- [ ] Composite FKs prove cross-row consistency where a child copies a parent's keys.
