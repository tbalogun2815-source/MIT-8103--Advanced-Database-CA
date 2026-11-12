-- =====================================================================
-- Portfolio 3: COMMIT, ROLLBACK, failure and idempotency demos
-- Run from PowerShell (not from inside psql), from the project folder:
--
--   psql -U postgres -h localhost -d quickfund_db -a -f portfolio-3-transactions-concurrency/03_commit_rollback_demo.sql *> portfolio-3-transactions-concurrency/output/03_commit_rollback_output.txt
--
-- "-a" echoes each statement next to its result. "*>" saves everything
-- (statements, results and the deliberate errors in Demos 3 and 5) to the
-- output file. psql is needed because the file uses \echo and \gset,
-- which pgAdmin does not support. Requires 01_transfer_function.sql.
-- =====================================================================

\pset pager off

-- Two real ACTIVE accounts (sender balance must be well above 500)
\set acct1 '2000000955'
\set acct2 '2000000992'

\echo
\echo '=== Starting balances'
SELECT account_number, balance FROM accounts
WHERE account_number IN (:'acct1', :'acct2') ORDER BY account_number;

-- ---------------------------------------------------------------------
\echo
\echo '=== Demo 1: COMMIT. Transfer 100.00 and keep it.'
SELECT 'demo-commit-' || gen_random_uuid() AS k \gset
BEGIN;
SELECT transfer_funds(:'acct1', :'acct2', 100.00, :'k') AS transaction_id;
\echo '--- inside the transaction (not yet visible to other sessions):'
SELECT account_number, balance FROM accounts
WHERE account_number IN (:'acct1', :'acct2') ORDER BY account_number;
COMMIT;
\echo '--- after COMMIT (permanent):'
SELECT account_number, balance FROM accounts
WHERE account_number IN (:'acct1', :'acct2') ORDER BY account_number;

-- ---------------------------------------------------------------------
\echo
\echo '=== Demo 2: ROLLBACK. Transfer 100.00, then change our mind.'
SELECT 'demo-rollback-' || gen_random_uuid() AS k \gset
BEGIN;
SELECT transfer_funds(:'acct1', :'acct2', 100.00, :'k') AS transaction_id;
\echo '--- inside the transaction the money has moved:'
SELECT account_number, balance FROM accounts
WHERE account_number IN (:'acct1', :'acct2') ORDER BY account_number;
ROLLBACK;
\echo '--- after ROLLBACK the balances are back to what they were:'
SELECT account_number, balance FROM accounts
WHERE account_number IN (:'acct1', :'acct2') ORDER BY account_number;
\echo '--- and no trace of that transaction remains:'
SELECT count(*) AS rows_for_rolled_back_key FROM transactions WHERE idempotency_key = :'k';

-- ---------------------------------------------------------------------
\echo
\echo '=== Demo 3: automatic rollback on failure (insufficient funds).'
\echo '--- the next statement is EXPECTED to fail:'
BEGIN;
SELECT transfer_funds(:'acct1', :'acct2', 999999999.00, 'demo-too-big');
ROLLBACK;
\echo '--- the failed attempt changed nothing:'
SELECT account_number, balance FROM accounts
WHERE account_number IN (:'acct1', :'acct2') ORDER BY account_number;
SELECT count(*) AS rows_for_failed_key FROM transactions WHERE idempotency_key = 'demo-too-big';

-- ---------------------------------------------------------------------
\echo
\echo '=== Demo 4: idempotency. The same request sent twice is applied once.'
SELECT 'demo-idem-' || gen_random_uuid() AS k \gset
SELECT transfer_funds(:'acct1', :'acct2', 25.00, :'k') AS first_call;
SELECT transfer_funds(:'acct1', :'acct2', 25.00, :'k') AS retry_same_id;
SELECT count(*) AS transactions_with_this_key FROM transactions WHERE idempotency_key = :'k';
SELECT account_number, balance FROM accounts
WHERE account_number IN (:'acct1', :'acct2') ORDER BY account_number;

-- ---------------------------------------------------------------------
\echo
\echo '=== Demo 5: SAVEPOINT. Undo one failed step without losing earlier work.'
SELECT 'demo-sp-' || gen_random_uuid() AS k \gset
BEGIN;
SELECT transfer_funds(:'acct1', :'acct2', 10.00, :'k') AS first_transfer;
SAVEPOINT before_second_transfer;
\echo '--- the next statement is EXPECTED to fail:'
SELECT transfer_funds(:'acct1', :'acct2', 999999999.00, 'demo-sp-too-big');
ROLLBACK TO SAVEPOINT before_second_transfer;
\echo '--- the first transfer is still alive inside the transaction:'
SELECT account_number, balance FROM accounts
WHERE account_number IN (:'acct1', :'acct2') ORDER BY account_number;
COMMIT;

-- ---------------------------------------------------------------------
\echo
\echo '=== Double-entry evidence: the latest ledger lines for these accounts'
SELECT l.transaction_id, a.account_number, l.entry_direction, l.amount
FROM ledger_entries l
JOIN accounts a ON a.account_id = l.account_id
WHERE a.account_number IN (:'acct1', :'acct2')
ORDER BY l.created_at DESC, l.entry_id DESC
LIMIT 8;