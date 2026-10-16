-- name: Post a wallet debit (row lock, idempotent)
-- kind: transactional
-- mode: dml
SELECT billing.post_ledger_entry(:wallet, 'consumption', -1, 'bench-' || clock_timestamp()::text);
