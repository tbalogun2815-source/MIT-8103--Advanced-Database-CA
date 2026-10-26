-- Q2: Daily completed transfer totals for 30 days

-- Computes daily completed transfer counts and aggregate transaction amounts over the last 30 days.
-- Filters specifically for completed transfers (status = 'SUCCESS') grouped by day.
-- Note: If running against static historical seed data, replace CURRENT_DATE with (SELECT MAX(completed_at)::date FROM transactions).
SELECT
    DATE_TRUNC('day', completed_at) AS transfer_day,
    COUNT(*) AS total_transfers,
    SUM(amount) AS total_amount
FROM transactions
WHERE transaction_type = 'TRANSFER'
  AND status = 'SUCCESS'
  AND completed_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', completed_at)
ORDER BY transfer_day DESC;
