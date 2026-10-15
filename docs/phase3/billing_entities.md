# Subscriptions, wallet, payments and download history: entities (M11) — owner C

Backlogs B38, B41, B44, B47. DDL: `ddl/70_billing.sql`. Tests: `tests/constraints/m14_billing.sql`. Relationships: `docs/phase3/billing_relationships.md`.

Rows were drafted from the DDL comments with `tools/draft_design_docs.py` and reviewed. The m05 comparison keeps them equal to the catalog.

## Key rules
- RG10: `ex_subscription_licence_period` (periods of one licence never overlap; cancelled ones are excluded). Renewal is a new subscription linked by `subscription_renewal`; cancellation is a row that marks the subscription cancelled.
- Ledger: append-only, with a correction as a reversing entry (`reverses_entry_id`, each entry reversed at most once). Sign rules per entry type; running `balance_after`.
- `billing.post_ledger_entry` is the only write path for money. It locks the wallet row, is idempotent by key, and keeps `wallet.balance` = sum of the ledger; `ck_wallet_balance_non_negative` stops overdrafts.
- Payments: no card or bank data; gateway tokens are Sensitive. Webhooks are append-only and integration-write, idempotent by (gateway, event id), and move the order status. Refunds lock the order and never exceed the payment (`trg_refund_within_payment`).
- Download history: each download references its consumption debit (`trg_profile_download_event_debit`); `billing.record_profile_download` debits, records consumption, writes the event and audits it in one transaction. Paid profile views link their debit as well.

## Entities
| entity | schema | module | purpose (one line) | tier | delete class | owner |
|---|---|---|---|---|---|---|
| profile_view_event | profile | Subscriptions, wallet, payments and download history | Stub from Phase 1, extended here: Which employer or recruiter viewed which profile, and when (profile view history). Paid views link their ledger debit in M14 | 1 | append-only | C |
| billing_cycle | ref | Subscriptions, wallet, payments and download history | Lookup: plan billing cycle. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| subscription_status | ref | Subscriptions, wallet, payments and download history | Lookup: subscription status. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| entitlement_type | ref | Subscriptions, wallet, payments and download history | Lookup: what a plan entitles the account to. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| payment_gateway | ref | Subscriptions, wallet, payments and download history | Lookup: payment gateway. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| payment_status | ref | Subscriptions, wallet, payments and download history | Lookup: payment order status. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| invoice_status | ref | Subscriptions, wallet, payments and download history | Lookup: invoice status. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| refund_status | ref | Subscriptions, wallet, payments and download history | Lookup: refund status. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| ledger_entry_type | ref | Subscriptions, wallet, payments and download history | Lookup: kind of wallet ledger entry. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| consumption_purpose | ref | Subscriptions, wallet, payments and download history | Lookup: what wallet credit was spent on. Rows are deactivated (is_active), not deleted, once referenced. | ref | hard-delete | C |
| plan | billing | Subscriptions, wallet, payments and download history | Commercial plan: price per cycle and the licence limits it grants; deactivated, not deleted, once sold | 1 | hard-delete | C |
| plan_entitlement | billing | Subscriptions, wallet, payments and download history | Quantity of an entitlement a plan includes per billing cycle (owned by the plan) | 1 | hard-delete | C |
| subscription | billing | Subscriptions, wallet, payments and download history | Paid period of a plan on a licence; periods of one licence never overlap. Renewal = a new row linked by subscription_renewal | 1 | hard-delete | C |
| subscription_renewal | billing | Subscriptions, wallet, payments and download history | Renewal: links a subscription to the one that continues it (each renewed at most once) | 1 | hard-delete | C |
| subscription_cancellation | billing | Subscriptions, wallet, payments and download history | Cancellation of a subscription (who = created_by); marks the subscription cancelled (trigger) | 1 | hard-delete | C |
| wallet | billing | Subscriptions, wallet, payments and download history | Prepaid wallet of an account in one currency; balance changes only through billing.post_ledger_entry and always equals the sum of its ledger | 1 | hard-delete | C |
| payment_order | billing | Subscriptions, wallet, payments and download history | Payment order sent to the gateway for a subscription or a wallet recharge; no card or bank data is stored (docket Section 6). Status follows payment_event | 1 | hard-delete | C |
| payment_event | billing | Subscriptions, wallet, payments and download history | Gateway webhook event (payment transaction history). A replayed event is rejected by (gateway, event id); each event moves the order status | 1 | append-only | C |
| invoice | billing | Subscriptions, wallet, payments and download history | Tax invoice for a payment order; corrections void the invoice and issue a new one | 1 | hard-delete | C |
| refund | billing | Subscriptions, wallet, payments and download history | Refund against a captured payment; the sum of non-failed refunds never exceeds the payment (trg_refund_within_payment) | 1 | hard-delete | C |
| wallet_ledger_entry | billing | Subscriptions, wallet, payments and download history | Wallet ledger: every recharge, consumption, refund, grant and correction (RG10). A correction reverses an earlier entry by a new row with the opposite amount | 1 | append-only | C |
| credit_consumption | billing | Subscriptions, wallet, payments and download history | What a ledger debit paid for: a job posting, an outreach batch, a profile download or view | 1 | append-only | C |
| profile_download_event | billing | Subscriptions, wallet, payments and download history | Which recruiter or employer downloaded which profile, when, and the ledger debit that paid for it. Partition monthly at full scale (M21) | 1 | append-only | C |

## Validation checklist (reviewer ticks)
- [ ] Every domain of this module in docket Section 7 has an entity.
- [ ] No two entities hold the same fact; earlier-phase tables are extended, not duplicated.
- [ ] Every enumeration has a lookup.
