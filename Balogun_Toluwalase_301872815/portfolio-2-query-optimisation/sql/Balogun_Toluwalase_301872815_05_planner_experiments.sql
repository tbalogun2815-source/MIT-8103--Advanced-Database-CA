-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 2 (Query Optimisation)
-- Script: 05_planner_experiments.sql
-- Description: PostgreSQL query planner experiments demonstrating:
--              - Experiment A: Engine configuration, cost constants, and relation sizes
--              - Experiment B: Index scan vs forced sequential scan on Q1 (Top-N heapsort)
--              - Experiment C: Index scan vs forced sequential scan on Q2 (Aggregation)
--              - Experiment D: Selectivity thresholds & plan choice (rare vs common values)
-- ============================================================================


-- ============================================================================
-- Experiment A: Environment, Memory & Cost Parameters
-- ============================================================================
\echo ============================================================================
\echo Experiment A: Environment & Planner Configuration
\echo ============================================================================

\echo ---- PostgreSQL Engine Version ----
SELECT version();

\echo ---- Storage & Memory Parameters ----
SHOW block_size;
SHOW shared_buffers;
SHOW work_mem;

\echo ---- Planner Cost Constants ----
SHOW seq_page_cost;
SHOW random_page_cost;
SHOW cpu_tuple_cost;

\echo ---- Table Storage Footprint (Data + Indexes) ----
SELECT
    table_name,
    pg_size_pretty(pg_total_relation_size(quote_ident(table_name)::regclass)) AS total_size,
    pg_size_pretty(pg_relation_size(quote_ident(table_name)::regclass)) AS table_size,
    pg_size_pretty(pg_indexes_size(quote_ident(table_name)::regclass)) AS index_size
FROM (
    VALUES
        ('customers'),
        ('accounts'),
        ('transactions'),
        ('ledger_entries')
) AS t(table_name);


-- ============================================================================
-- Experiment B: Index vs Forced Sequential Scan on Q1 (Account Statement)
-- ============================================================================
\echo ============================================================================
\echo Experiment B: Cost Comparison for Q1 (Default Index Scan vs Forced Seq Scan)
\echo ============================================================================

\echo ---- B.1: Q1 with Optimizer Default Settings ----
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

\echo ---- B.2: Force Disable Index Scans ----
SET enable_indexscan = off;
SET enable_bitmapscan = off;
SET enable_indexonlyscan = off;

\echo ---- B.3: Q1 with Index Scans Disabled (Sequential Scan Plan) ----
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

\echo ---- B.4: Reset Optimizer Settings to Default ----
RESET enable_indexscan;
RESET enable_bitmapscan;
RESET enable_indexonlyscan;


-- ============================================================================
-- Experiment C: Index vs Forced Sequential Scan on Q2 (Daily Transfer Totals)
-- ============================================================================
\echo ============================================================================
\echo Experiment C: Cost Comparison for Q2 (Default vs Forced Seq Scan)
\echo ============================================================================

\echo ---- C.1: Q2 with Optimizer Default Settings ----
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

\echo ---- C.2: Force Disable Index Scans ----
SET enable_indexscan = off;
SET enable_bitmapscan = off;
SET enable_indexonlyscan = off;

\echo ---- C.3: Q2 with Index Scans Disabled (Sequential Scan Plan) ----
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

\echo ---- C.4: Reset Optimizer Settings to Default ----
RESET enable_indexscan;
RESET enable_bitmapscan;
RESET enable_indexonlyscan;


-- ============================================================================
-- Experiment D: Selectivity & Costing (Rare vs Common Value Scans)
-- ============================================================================
-- Schema alignment note:
-- The customers table in QuickFund uses 'customer_type' as its classification column
-- (CHECK customer_type IN ('INDIVIDUAL', 'MERCHANT')). In seed data:
--   - 'MERCHANT'   = 501 rows (~10% of table, the RARE value)
--   - 'INDIVIDUAL' = 4,500 rows (~90% of table, the COMMON value)
-- The index idx_tmp_customers_status is created on customers (customer_type) to test
-- planner behavior on rare vs common selectivity thresholds using real schema columns.
-- ============================================================================
\echo ============================================================================
\echo Experiment D: Selectivity & Costing (Rare vs Common Values)
\echo ============================================================================

\echo ---- D.1: Create Temporary Index and Collect Statistics ----
CREATE INDEX idx_tmp_customers_status ON customers (customer_type);
ANALYZE customers;

\echo ---- D.2: Query Rare Value (customer_type = 'MERCHANT', ~10% selectivity -> favors Index Scan) ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM customers WHERE customer_type = 'MERCHANT';

\echo ---- D.3: Query Common Value (customer_type = 'INDIVIDUAL', ~90% selectivity -> favors Seq Scan) ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM customers WHERE customer_type = 'INDIVIDUAL';

\echo ---- D.4: Drop Temporary Index ----
DROP INDEX idx_tmp_customers_status;
