-- Q5: Look up a transaction by idempotency key

-- Point lookup of a financial transaction using its unique idempotency key to prevent double charging.
-- Dynamically selects a real transfer idempotency key via subquery to ensure the query executes out of the box.
SELECT
    transaction_id,
    idempotency_key,
    transaction_type,
    amount,
    currency,
    reversal_of,
    status,
    description,
    created_at,
    completed_at
FROM transactions
WHERE idempotency_key = (
    SELECT idempotency_key
    FROM transactions
    WHERE transaction_type = 'TRANSFER'
    ORDER BY created_at ASC
    LIMIT 1
);
