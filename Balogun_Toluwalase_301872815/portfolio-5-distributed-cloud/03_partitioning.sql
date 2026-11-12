-- =====================================================================
-- Portfolio 5: hash partitioning of the ledger (a single-node model of sharding)
-- Run on the PRIMARY after the QuickFund data has been loaded.
-- Safe to re-run.
-- =====================================================================
\echo '=== Rebuilding the partitioned copy of ledger_entries'
DROP TABLE IF EXISTS ledger_entries_sharded;

-- Partition key = account_id. All ledger lines of one wallet land in the SAME
-- partition, so an account statement touches exactly one partition.
-- (Primary keys and unique constraints on a partitioned table must include the
-- partition key, so the original rule UNIQUE (transaction_id, account_id,
-- entry_direction) becomes UNIQUE (account_id, transaction_id, entry_direction).)
CREATE TABLE ledger_entries_sharded (
    entry_id        UUID           NOT NULL,
    transaction_id  UUID           NOT NULL,
    account_id      UUID           NOT NULL,
    entry_direction VARCHAR(10)    NOT NULL,
    amount          NUMERIC(15, 2) NOT NULL,
    created_at      TIMESTAMPTZ    NOT NULL,
    PRIMARY KEY (account_id, entry_id),
    CONSTRAINT uq_sharded_account_tx_direction UNIQUE (account_id, transaction_id, entry_direction)
) PARTITION BY HASH (account_id);

CREATE TABLE ledger_shard_0 PARTITION OF ledger_entries_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE ledger_shard_1 PARTITION OF ledger_entries_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE ledger_shard_2 PARTITION OF ledger_entries_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE ledger_shard_3 PARTITION OF ledger_entries_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 3);

INSERT INTO ledger_entries_sharded (entry_id, transaction_id, account_id, entry_direction, amount, created_at)
SELECT entry_id, transaction_id, account_id, entry_direction, amount, created_at
FROM ledger_entries;

ANALYZE ledger_entries_sharded;

-- Real ids to use in the EXPLAIN queries below.
SELECT account_id AS sample_account FROM accounts WHERE account_number = '2000000955' \gset
SELECT transaction_id AS sample_txn FROM ledger_entries_sharded LIMIT 1 \gset

\echo
\echo '=== Rows per partition (hash spreads accounts roughly evenly)'
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM ledger_entries_sharded
GROUP BY 1 ORDER BY 1;

\echo
\echo '=== Same total as the original table? (expected: both numbers equal)'
SELECT (SELECT count(*) FROM ledger_entries)         AS original_rows,
       (SELECT count(*) FROM ledger_entries_sharded) AS partitioned_rows;

\echo
\echo '=== Query WITH the partition key: only ONE partition is scanned (partition pruning)'
EXPLAIN (COSTS OFF)
SELECT * FROM ledger_entries_sharded WHERE account_id = :'sample_account' ORDER BY created_at DESC LIMIT 10;

\echo
\echo '=== Query WITHOUT the partition key: ALL four partitions are scanned'
EXPLAIN (COSTS OFF)
SELECT * FROM ledger_entries_sharded WHERE transaction_id = :'sample_txn';

\echo
\echo '=== One transfer = two ledger lines. Which shard holds each line?'
SELECT tableoid::regclass AS partition, entry_direction, account_id
FROM ledger_entries_sharded
WHERE transaction_id = :'sample_txn'
ORDER BY entry_direction;

\echo
\echo '=== How many transactions touch 1 shard vs 2 shards? (2 = a cross-shard transfer)'
SELECT shards_touched, count(*) AS transactions
FROM (
    SELECT transaction_id, count(DISTINCT tableoid) AS shards_touched
    FROM ledger_entries_sharded
    GROUP BY transaction_id
) t
GROUP BY shards_touched
ORDER BY shards_touched;