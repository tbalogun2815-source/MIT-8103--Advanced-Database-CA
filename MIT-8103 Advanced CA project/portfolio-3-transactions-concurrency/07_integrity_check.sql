-- =====================================================================
-- Portfolio 3: integrity check. Run BEFORE and AFTER the stress tests.
-- Expected: total_money_in_system is identical every time, and the
-- three problem counts are all 0.
-- Demo wallets (9000000001/2) are excluded: they were funded outside the
-- ledger. The capital seed deposit (one-sided by design) is excluded
-- from the debit/credit balance check.
-- =====================================================================

\pset pager off

-- 1. Money is neither created nor destroyed by transfers.
SELECT sum(balance) AS total_money_in_system
FROM accounts
WHERE account_number NOT IN ('9000000001', '9000000002');

-- 2. Stress-test transfers recorded, and their ledger lines (2 per transfer).
SELECT
    (SELECT count(*) FROM transactions
     WHERE idempotency_key LIKE 'pgb-%' AND status = 'SUCCESS') AS stress_transfers,
    (SELECT count(*) FROM ledger_entries l
     JOIN transactions t ON t.transaction_id = l.transaction_id
     WHERE t.idempotency_key LIKE 'pgb-%') AS stress_ledger_lines;

-- 3. Every transaction's debits must equal its credits. Expected: 0
SELECT count(*) AS unbalanced_transactions
FROM (
    SELECT transaction_id
    FROM ledger_entries
    WHERE transaction_id <> '00000000-0000-0000-0000-000000000003'
    GROUP BY transaction_id
    HAVING SUM(CASE WHEN entry_direction = 'DEBIT' THEN amount ELSE -amount END) <> 0
) x;

-- 4. accounts.balance must equal the ledger total (credits minus debits)
--    for every ledger-backed account. Expected: 0
SELECT count(*) AS mismatched_accounts
FROM accounts a
JOIN (
    SELECT account_id,
           SUM(CASE WHEN entry_direction = 'CREDIT' THEN amount ELSE -amount END) AS net
    FROM ledger_entries
    GROUP BY account_id
) l ON l.account_id = a.account_id
WHERE a.account_number NOT IN ('9000000001', '9000000002')
  AND a.balance <> l.net;

-- 5. No stress-test transaction left half-finished. Expected: 0
SELECT count(*) AS stuck_pending_transactions
FROM transactions
WHERE idempotency_key LIKE 'pgb-%' AND status = 'PENDING';