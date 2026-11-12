-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 2 (Query Optimisation)
-- Script: 03_create_indexes.sql
-- Description: DDL script creating targeted B-tree, covering, and partial
--              indexes to optimize execution plans across portfolio queries.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Index 1: Composite Index on ledger_entries for Q1 and Q3
-- Serves:
--   - Q1 (Account Statement: fetch 50 newest ledger entries for an account)
--   - Q3 (Customer Largest Transfers: joins customer accounts to debit entries)
-- Column Order Rationale:
--   1. account_id (leading): High-selectivity equality/join predicate in Q1
--      (WHERE le.account_id = ...) and Q3 (JOIN ... ON a.account_id = le.account_id).
--      PostgreSQL can jump straight to the matching account's entries via B-tree seek.
--   2. created_at DESC (trailing): Matches the ORDER BY le.created_at DESC in Q1,
--      allowing an ordered index traversal that satisfies the LIMIT 50 directly,
--      eliminating the need for an in-memory or on-disk Top-N sort.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_ledger_entries_account_created_at_desc
ON ledger_entries (account_id, created_at DESC);


-- ----------------------------------------------------------------------------
-- Index 2: Single-column Foreign Key Index on accounts for Q3
-- Serves:
--   - Q3 (Customer Largest Transfers)
--   - Also accelerates foreign key joins from customers to accounts in Q4 & Q10
-- Column Order Rationale:
--   1. customer_id: In Q3, the customer filter resolves to a single customer_id.
--      Indexing accounts(customer_id) enables a direct Index Scan / Nested Loop
--      join to locate the customer's account records in O(log N) rather than
--      performing a full table scan on accounts.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_accounts_customer_id
ON accounts (customer_id);


-- ----------------------------------------------------------------------------
-- Index 3: Partial Covering Index on Completed Transfers by Time for Q2
-- Serves:
--   - Q2 (Daily Completed Transfer Totals for 30 Days)
-- Column Order Rationale:
--   1. completed_at DESC (key): Directly accelerates the 30-day range predicate
--      (WHERE completed_at >= CURRENT_DATE - INTERVAL '30 days') and feeds rows
--      pre-sorted for GROUP BY DATE_TRUNC('day', completed_at) ORDER BY transfer_day DESC.
--   2. INCLUDE (amount): Stores transaction amount in the leaf payload, turning
--      the query into a 100% Index Only Scan (satisfying COUNT(*) and SUM(amount))
--      with zero heap lookups.
--   3. WHERE transaction_type = 'TRANSFER' AND status = 'SUCCESS':
--      Partial filter isolates only successful transfers, filtering out pending,
--      failed, reversed transactions and non-transfer types, keeping index size minimal.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_transactions_transfers_completed_time
ON transactions (completed_at DESC)
INCLUDE (amount)
WHERE transaction_type = 'TRANSFER' AND status = 'SUCCESS';


-- ----------------------------------------------------------------------------
-- Index 4: Partial Covering Index on Debit Ledger Entries for Q4
-- Serves:
--   - Q4 (Customers with the Most Large Transfers / Fraud Review)
-- Column Order Rationale:
--   1. transaction_id (leading key): Join column to transactions (le.transaction_id = t.transaction_id).
--   2. account_id (second key): Join column to accounts (le.account_id = a.account_id).
--   3. WHERE entry_direction = 'DEBIT': Partial filter eliminates all CREDIT entries,
--      halving the index footprint. Because both joined columns (transaction_id, account_id)
--      are present in the index, PostgreSQL can satisfy the scan on ledger_entries
--      entirely via an Index Only Scan without visiting table heap pages.
--   Note on 'large': In Q4, the threshold filter t.amount >= 350.00 is evaluated
--   against transactions.amount. Because PostgreSQL's planner cannot infer across
--   table boundaries that le.amount = t.amount without an explicit join clause on
--   amount, a partial predicate of WHERE entry_direction = 'DEBIT' on ledger_entries
--   ensures the query planner can safely match and use this index during execution.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_ledger_entries_debit_covering
ON ledger_entries (transaction_id, account_id)
WHERE entry_direction = 'DEBIT';


-- ----------------------------------------------------------------------------
-- Index 5: Covering Index on Transactions for Q8
-- Serves:
--   - Q8 (Net Transfer Movement Without Counting Reversed Transfers)
-- Column Order Rationale:
--   1. transaction_type (leading key): Satisfies the equality predicate
--      (WHERE transaction_type = 'TRANSFER').
--   2. created_at DESC (trailing key): Facilitates streaming rows ordered by timestamp
--      to compute GROUP BY DATE_TRUNC('day', created_at) ORDER BY transfer_day DESC.
--   3. INCLUDE (status, amount): Non-key payload columns required for aggregate
--      computations (COUNT(*), SUM(amount), FILTER (WHERE status = 'SUCCESS'),
--      FILTER (WHERE status = 'REVERSED')), enabling a complete Index Only Scan.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_transactions_type_time_covering
ON transactions (transaction_type, created_at DESC)
INCLUDE (status, amount);


-- ----------------------------------------------------------------------------
-- Index 6: Partial Covering Index on Failed Transactions for Q10
-- Serves:
--   - Q10 (Customers with the Most Failed Transactions in the Last 30 Days)
-- Column Order Rationale:
--   1. created_at DESC (key): Directly indexes the date range filter
--      (WHERE created_at >= CURRENT_DATE - INTERVAL '30 days') in reverse chronological order.
--   2. INCLUDE (amount): Stores amount in leaf pages, which together with the primary key
--      (transaction_id) enables an Index Only Scan on transactions for COUNT(t.transaction_id)
--      and SUM(t.amount).
--   3. WHERE status = 'FAILED': Partial predicate isolates the rare minority of failed
--      transactions (<1% of system traffic), creating a tiny, highly efficient index
--      that completely avoids scanning successful or pending transactions.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_transactions_failed_recent
ON transactions (created_at DESC)
INCLUDE (amount)
WHERE status = 'FAILED';


-- ----------------------------------------------------------------------------
-- Index 7: Covering Index on Successful Transactions for Monthly Volume (Q11)
-- Serves:
--   - Q11 (Total Count and Monetary Volume of Completed Transactions Per Month)
-- Column Order Rationale:
--   1. created_at DESC (key): Sorts successful transactions chronologically,
--      aiding GROUP BY DATE_TRUNC('month', created_at) ORDER BY transaction_month DESC.
--   2. INCLUDE (transaction_type, amount): Carries the payload columns required for
--      conditional filtering (WHERE transaction_type = 'TRANSFER',
--      WHERE transaction_type = 'DEPOSIT') and sums, converting a full table scan
--      (206,000+ rows) into an Index Only Scan.
--   3. WHERE status = 'SUCCESS': Partial filter restricts index entries exclusively to
--      settled transactions matching WHERE status = 'SUCCESS', discarding unneeded rows.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_transactions_success_monthly
ON transactions (created_at DESC)
INCLUDE (transaction_type, amount)
WHERE status = 'SUCCESS';


-- ============================================================================
-- VERIFICATION: Index Storage Footprint
-- Queries pg_indexes and pg_class to report the physical disk size of each
-- optimization index created above.
-- ============================================================================
SELECT
    i.schemaname,
    i.tablename,
    i.indexname,
    pg_size_pretty(pg_relation_size(c.oid)) AS index_size
FROM pg_indexes i
JOIN pg_class c ON c.relname = i.indexname
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = i.schemaname
WHERE i.indexname IN (
    'idx_ledger_entries_account_created_at_desc',
    'idx_accounts_customer_id',
    'idx_transactions_transfers_completed_time',
    'idx_ledger_entries_debit_covering',
    'idx_transactions_type_time_covering',
    'idx_transactions_failed_recent',
    'idx_transactions_success_monthly'
)
ORDER BY i.tablename, i.indexname;
