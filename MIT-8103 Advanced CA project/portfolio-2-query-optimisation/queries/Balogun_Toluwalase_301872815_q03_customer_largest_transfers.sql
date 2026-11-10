-- Q3: A customer's 10 largest outgoing transfers

-- Retrieves the 10 largest outgoing transfers for a specific customer.
-- Note on Schema: transactions has no direct account/customer foreign key;
-- it joins to accounts via ledger_entries (entry_direction = 'DEBIT' identifies outgoing transfers).
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    a.account_number,
    t.transaction_id,
    t.idempotency_key,
    t.amount AS transfer_amount,
    t.currency,
    t.status AS transfer_status,
    t.created_at AS transfer_time,
    t.description
FROM customers c
JOIN accounts a ON c.customer_id = a.customer_id
JOIN ledger_entries le ON a.account_id = le.account_id
JOIN transactions t ON le.transaction_id = t.transaction_id
WHERE c.customer_id = (
    SELECT customer_id
    FROM customers
    WHERE customer_type = 'INDIVIDUAL'
    ORDER BY created_at ASC
    LIMIT 1
)
  AND t.transaction_type = 'TRANSFER'
  AND le.entry_direction = 'DEBIT'
ORDER BY t.amount DESC
LIMIT 10;
