-- Q1: Show a customer their 50 newest ledger lines

-- Fetches the 50 newest ledger entries for a single account joined with transaction details.
-- Uses an accounts subquery ordered by created_at to select the target account dynamically.
SELECT
    le.entry_id,
    le.account_id,
    le.entry_direction,
    le.amount AS entry_amount,
    le.created_at AS entry_created_at,
    t.transaction_id,
    t.idempotency_key,
    t.transaction_type,
    t.amount AS transaction_amount,
    t.currency,
    t.status AS transaction_status,
    t.description,
    t.completed_at
FROM ledger_entries le
JOIN transactions t ON le.transaction_id = t.transaction_id
WHERE le.account_id = (
    SELECT account_id
    FROM accounts
    ORDER BY created_at ASC
    LIMIT 1
)
ORDER BY le.created_at DESC
LIMIT 50;
