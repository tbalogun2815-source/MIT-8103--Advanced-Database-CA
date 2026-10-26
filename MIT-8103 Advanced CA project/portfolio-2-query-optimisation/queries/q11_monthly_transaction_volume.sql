-- Q11: What is the total count and monetary volume of completed transactions per month?

-- Business Purpose: Track platform growth, liquidity throughput, and product adoption trends over time,
-- providing leadership with monthly counts, aggregate volumes, average ticket sizes, and category breakdowns.
SELECT
    DATE_TRUNC('month', created_at) AS transaction_month,
    COUNT(*) AS total_transaction_count,
    SUM(amount) AS total_transaction_amount,
    ROUND(AVG(amount), 2) AS average_transaction_amount,
    COUNT(*) FILTER (WHERE transaction_type = 'TRANSFER') AS transfer_count,
    COALESCE(SUM(amount) FILTER (WHERE transaction_type = 'TRANSFER'), 0.00) AS transfer_amount,
    COUNT(*) FILTER (WHERE transaction_type = 'DEPOSIT') AS deposit_count,
    COALESCE(SUM(amount) FILTER (WHERE transaction_type = 'DEPOSIT'), 0.00) AS deposit_amount
FROM transactions
WHERE status = 'SUCCESS'
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY transaction_month DESC;
