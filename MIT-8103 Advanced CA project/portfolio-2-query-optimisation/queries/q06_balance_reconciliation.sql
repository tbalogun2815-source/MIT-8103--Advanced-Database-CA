-- Q6: Does every cached balance match the ledger? (must return 0 rows)

-- Reconciles stored accounts.balance against the calculated sum of immutable ledger entries.
-- Mathematical ledger balance formula: SUM(Credits) - SUM(Debits).
-- Returns 0 rows if the cached balances are 100% consistent with the double-entry ledger.
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
