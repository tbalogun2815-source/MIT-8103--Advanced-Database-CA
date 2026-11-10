-- Q4: Customers with the most large transfers (fraud review)

-- Identifies the top 20 customers with the highest frequency of large outgoing transfers for fraud review.
-- Threshold: In QuickFund seed data, transfer amounts range between 20.00 and 399.99 NGN; >= 350.00 NGN isolates the top tier.
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    COUNT(t.transaction_id) AS large_transfer_count,
    SUM(t.amount) AS total_large_transfer_volume
FROM customers c
JOIN accounts a ON c.customer_id = a.customer_id
JOIN ledger_entries le ON a.account_id = le.account_id
JOIN transactions t ON le.transaction_id = t.transaction_id
WHERE t.transaction_type = 'TRANSFER'
  AND le.entry_direction = 'DEBIT'
  AND t.amount >= 350.00
GROUP BY c.customer_id, c.first_name, c.last_name, c.email
ORDER BY large_transfer_count DESC, total_large_transfer_volume DESC
LIMIT 20;
