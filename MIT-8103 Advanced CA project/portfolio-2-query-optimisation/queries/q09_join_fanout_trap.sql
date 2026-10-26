-- Q9: Why summing after a join gives double the true total

-- Demonstrates the relational join fan-out trap in a double-entry bookkeeping schema.
-- In QuickFund, each transfer has exactly two ledger entries (1 DEBIT leg and 1 CREDIT leg).
-- Joining transactions to ledger_entries duplicates each transaction row, causing SUM(t.amount)
-- to be exactly double the true aggregate transfer volume.
SELECT
    (SELECT SUM(amount) FROM transactions WHERE transaction_type = 'TRANSFER') AS correct_total,
    SUM(t.amount) AS fan_out_total
FROM transactions t
JOIN ledger_entries le ON t.transaction_id = le.transaction_id
WHERE t.transaction_type = 'TRANSFER';
