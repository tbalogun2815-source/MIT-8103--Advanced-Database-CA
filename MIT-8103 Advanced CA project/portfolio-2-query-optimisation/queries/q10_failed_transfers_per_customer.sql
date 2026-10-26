-- Q10: Which customers had the most failed transactions in the last 30 days?

-- Business Purpose: Identify customers experiencing high transaction friction, payment gateway failures,
-- or potential fraud attempts requiring customer support and compliance risk intervention.
-- Schema Bridge: Joins customers -> accounts -> ledger_entries -> transactions.
-- Uses entry_direction = 'DEBIT' to attribute failed outgoing transactions to the initiating customer.
-- Note: If running against static historical seed data, replace CURRENT_DATE with (SELECT MAX(created_at)::date FROM transactions).
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.phone,
    COUNT(t.transaction_id) AS failed_transaction_count,
    SUM(t.amount) AS total_failed_amount
FROM customers c
JOIN accounts a ON c.customer_id = a.customer_id
JOIN ledger_entries le ON a.account_id = le.account_id
JOIN transactions t ON le.transaction_id = t.transaction_id
WHERE t.status = 'FAILED'
  AND le.entry_direction = 'DEBIT'
  AND t.created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.phone
ORDER BY failed_transaction_count DESC, total_failed_amount DESC
LIMIT 20;
