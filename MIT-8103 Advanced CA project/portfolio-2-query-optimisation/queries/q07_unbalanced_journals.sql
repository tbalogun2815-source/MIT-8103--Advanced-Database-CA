-- Q7: Does every transaction balance, debits equal credits? (must return 0 rows)

-- Validates that every financial transaction satisfies double-entry bookkeeping rules: SUM(Debits) = SUM(Credits).
-- Uses LEFT JOIN, FILTER aggregate clauses, and HAVING to isolate any unbalanced journals.
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


-- Q7b: same check excluding the capital seed transaction (reference TXN-CAPITAL-SEED-001), which is intentionally one-sided
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
