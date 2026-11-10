-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 2 (Query Optimisation)
-- Script: 04_drop_indexes.sql
-- Description: Teardown script dropping all optimization indexes created
--              in 03_create_indexes.sql to restore baseline performance state.
-- ============================================================================

DROP INDEX IF EXISTS idx_ledger_entries_account_created_at_desc;
DROP INDEX IF EXISTS idx_accounts_customer_id;
DROP INDEX IF EXISTS idx_transactions_transfers_completed_time;
DROP INDEX IF EXISTS idx_ledger_entries_debit_covering;
DROP INDEX IF EXISTS idx_transactions_type_time_covering;
DROP INDEX IF EXISTS idx_transactions_failed_recent;
DROP INDEX IF EXISTS idx_transactions_success_monthly;
