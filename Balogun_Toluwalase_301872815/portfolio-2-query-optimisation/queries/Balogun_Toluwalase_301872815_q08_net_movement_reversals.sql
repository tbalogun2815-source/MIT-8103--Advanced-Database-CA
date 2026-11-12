-- Q8: Net transfer movement without counting reversed transfers

-- Calculates daily transfer volumes using FILTER aggregates, isolating completed vs reversed transfers.
-- Excludes reversed transfers from the net completed transfer movement.
SELECT
    DATE_TRUNC('day', created_at) AS transfer_day,
    COUNT(*) AS total_transfers_initiated,
    SUM(amount) AS gross_transfer_volume,
    COUNT(*) FILTER (WHERE status = 'SUCCESS') AS completed_transfer_count,
    COALESCE(SUM(amount) FILTER (WHERE status = 'SUCCESS'), 0.00) AS net_completed_volume,
    COUNT(*) FILTER (WHERE status = 'REVERSED') AS reversed_transfer_count,
    COALESCE(SUM(amount) FILTER (WHERE status = 'REVERSED'), 0.00) AS reversed_transfer_volume
FROM transactions
WHERE transaction_type = 'TRANSFER'
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY transfer_day DESC;
