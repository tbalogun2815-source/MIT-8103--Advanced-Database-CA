-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 2 (Query Optimisation)
-- Script: 01_capture_plans.sql
-- Description: Baseline query plan capture script.
--              Executes EXPLAIN (ANALYZE, BUFFERS) across all portfolio queries
--              (q01-q08, q10, q11; skipping q09 correctness verification).
-- ============================================================================


-- ============================================================================
-- Q1: Show a customer their 50 newest ledger lines (q01_account_statement.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
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


-- ============================================================================
-- Q2: Daily completed transfer totals for 30 days (q02_daily_transfer_totals.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
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


-- ============================================================================
-- Q3: A customer's 10 largest outgoing transfers (q03_customer_largest_transfers.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
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


-- ============================================================================
-- Q4: Customers with the most large transfers (fraud review) (q04_large_transfer_fraud.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
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


-- ============================================================================
-- Q5: Look up a transaction by idempotency key (q05_idempotency_lookup.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
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


-- ============================================================================
-- Q6: Does every cached balance match the ledger? (q06_balance_reconciliation.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    a.account_id,
    a.account_number,
    a.account_name,
    a.balance AS stored_balance,
    COALESCE(SUM(
        CASE
            WHEN le.entry_direction = 'CREDIT' THEN le.amount
            WHEN le.entry_direction = 'DEBIT'  THEN -le.amount
            ELSE 0.00
        END
    ), 0.00) AS computed_ledger_balance,
    a.balance - COALESCE(SUM(
        CASE
            WHEN le.entry_direction = 'CREDIT' THEN le.amount
            WHEN le.entry_direction = 'DEBIT'  THEN -le.amount
            ELSE 0.00
        END
    ), 0.00) AS discrepancy
FROM accounts a
LEFT JOIN ledger_entries le ON a.account_id = le.account_id
GROUP BY a.account_id, a.account_number, a.account_name, a.balance
HAVING a.balance <> COALESCE(SUM(
    CASE
        WHEN le.entry_direction = 'CREDIT' THEN le.amount
        WHEN le.entry_direction = 'DEBIT'  THEN -le.amount
        ELSE 0.00
    END
), 0.00);


-- ============================================================================
-- Q7: Unbalanced journals audit (q07_unbalanced_journals.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    t.transaction_id,
    t.idempotency_key,
    t.transaction_type,
    t.amount AS transaction_amount,
    COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'DEBIT'), 0.00) AS total_debits,
    COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'CREDIT'), 0.00) AS total_credits,
    COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'DEBIT'), 0.00) -
    COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'CREDIT'), 0.00) AS imbalance
FROM transactions t
LEFT JOIN ledger_entries le ON t.transaction_id = le.transaction_id
GROUP BY t.transaction_id, t.idempotency_key, t.transaction_type, t.amount
HAVING COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'DEBIT'), 0.00) <>
       COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'CREDIT'), 0.00);


-- ============================================================================
-- Q7b: Unbalanced journals audit excluding capital seed (q07_unbalanced_journals.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    t.transaction_id,
    t.idempotency_key,
    t.transaction_type,
    t.amount AS transaction_amount,
    COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'DEBIT'), 0.00) AS total_debits,
    COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'CREDIT'), 0.00) AS total_credits,
    COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'DEBIT'), 0.00) -
    COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'CREDIT'), 0.00) AS imbalance
FROM transactions t
LEFT JOIN ledger_entries le ON t.transaction_id = le.transaction_id
WHERE t.idempotency_key <> 'TXN-CAPITAL-SEED-001'
GROUP BY t.transaction_id, t.idempotency_key, t.transaction_type, t.amount
HAVING COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'DEBIT'), 0.00) <>
       COALESCE(SUM(le.amount) FILTER (WHERE le.entry_direction = 'CREDIT'), 0.00);


-- ============================================================================
-- Q8: Net transfer movement without counting reversed transfers (q08_net_movement_reversals.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
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


-- ============================================================================
-- Q10: Customers with the most failed transactions in the last 30 days (q10_failed_transfers_per_customer.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
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


-- ============================================================================
-- Q11: Number and total amount of transactions per month (q11_monthly_transaction_volume.sql)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
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
