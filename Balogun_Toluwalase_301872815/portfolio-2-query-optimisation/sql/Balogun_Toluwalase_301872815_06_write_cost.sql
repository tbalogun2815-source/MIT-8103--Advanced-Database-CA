-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 2 (Query Optimisation)
-- Script: 06_write_cost.sql
-- Description: Empirical write-amplification benchmark measuring the ingestion
--              latency and storage footprint penalty of maintaining B-Tree
--              indexes on the high-volume ledger_entries table.
-- ============================================================================


-- ============================================================================
-- Step 1: Enable Execution Timing
-- Activates psql query timing to display real wall-clock execution duration (ms)
-- for each subsequent statement, enabling direct comparison of insert latencies.
-- ============================================================================
\timing on


-- ============================================================================
-- Step 2: Informational Labels
-- Emits psql console banners to demarcate each phase of the benchmark.
-- ============================================================================
\echo ============================================================================
\echo Write Overhead Benchmark: Unindexed vs Indexed Bulk Ingestion
\echo ============================================================================

-- Clean up any prior temporary tables from the current session for idempotency
DROP TABLE IF EXISTS ledger_no_index;
DROP TABLE IF EXISTS ledger_with_index;


-- ============================================================================
-- Step 3: Create Unindexed Temporary Table
-- Clones the table definition of ledger_entries using EXCLUDING ALL so that
-- no primary keys, foreign keys, constraints, or indexes are copied.
-- This serves as the pure heap-only baseline for write performance.
-- ============================================================================
\echo ---- Step 3: Create unindexed temporary table (ledger_no_index) ----
CREATE TEMP TABLE ledger_no_index (LIKE ledger_entries EXCLUDING ALL);


-- ============================================================================
-- Step 4: Create Indexed Temporary Table
-- Clones the identical schema structure of ledger_entries using EXCLUDING ALL.
-- Indexes will be built on this table prior to data insertion in Step 5.
-- ============================================================================
\echo ---- Step 4: Create indexed temporary table (ledger_with_index) ----
CREATE TEMP TABLE ledger_with_index (LIKE ledger_entries EXCLUDING ALL);


-- ============================================================================
-- Step 5: Create Two B-Tree Indexes on ledger_with_index
-- Replicates typical read-optimization indexes on the ledger:
--   1. (account_id, created_at DESC) - composite index for account statement feeds (Q1 & Q3).
--   2. (created_at) - single-column index for timestamp range scans.
-- Both indexes must be maintained concurrently by PostgreSQL on every INSERT.
-- ============================================================================
\echo ---- Step 5: Create two indexes on ledger_with_index only ----
CREATE INDEX idx_temp_ledger_account_created_at_desc
ON ledger_with_index (account_id, created_at DESC);

CREATE INDEX idx_temp_ledger_created_at
ON ledger_with_index (created_at);


-- ============================================================================
-- Step 6: Bulk Ingestion into Unindexed Table
-- Copies all ledger rows from the source table into ledger_no_index.
-- With no secondary structures to maintain, writes are strictly append-only
-- heap page allocations, yielding maximum ingestion throughput.
-- ============================================================================
\echo ---- Step 6: Insert into unindexed table (measuring baseline heap write time) ----
INSERT INTO ledger_no_index SELECT * FROM ledger_entries;


-- ============================================================================
-- Step 7: Bulk Ingestion into Indexed Table
-- Copies the exact same ledger rows into ledger_with_index.
-- For every inserted tuple, PostgreSQL must write the heap row and perform two
-- B-Tree node traversals and leaf page updates, illustrating the write tax.
-- ============================================================================
\echo ---- Step 7: Insert into indexed table (measuring write time with 2 indexes) ----
INSERT INTO ledger_with_index SELECT * FROM ledger_entries;


-- ============================================================================
-- Step 8: Compare Row Counts and Physical Storage Footprint
-- Compares row counts and evaluates storage consumption using pg_total_relation_size
-- (total bytes including all forks and indexes), pg_relation_size (heap data only),
-- and pg_indexes_size (index overhead).
-- ============================================================================
\echo ---- Step 8: Storage footprint and row count comparison ----
SELECT
    table_name,
    row_count,
    pg_size_pretty(pg_total_relation_size(table_name::regclass)) AS total_size,
    pg_size_pretty(pg_relation_size(table_name::regclass)) AS heap_table_size,
    pg_size_pretty(pg_indexes_size(table_name::regclass)) AS index_overhead_size
FROM (
    SELECT 'ledger_no_index' AS table_name, COUNT(*) AS row_count FROM ledger_no_index
    UNION ALL
    SELECT 'ledger_with_index' AS table_name, COUNT(*) AS row_count FROM ledger_with_index
) summary;
