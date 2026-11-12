# MIT 8103 Advanced Database Systems — Final Executive Summary & Engineering Report
## Enterprise Database Architecture for QuickFund Digital Wallet & Financial Ledger System

> **Course Code:** MIT 8103
> **Course Title:** Advanced Database Systems
> **Student Name:** Balogun Toluwalase
> **Student ID:** 301872815
> **Degree Program:** Master of Information Technology (MIT)
> **Institution:** Miva Open University
> **Submission Date:** November 12, 2026
> **Repository:** https://github.com/tbalogun2815-source/MIT-8103--Advanced-Database-CA.git

---

## 1. Executive Summary & Project Genesis

Modern retail financial technology platforms operate under non-negotiable requirements: money transfers must execute atomically and with mathematical precision, wallet balances must never drift or enter unauthorized negative states, high-volume concurrent transfers must never deadlock, identity verification records must be stored with schema enforcement, and the underlying storage architecture must remain available, performant, and partition-tolerant under fluctuating transaction loads.

**QuickFund** is an enterprise-grade digital wallet and financial ledger database architecture developed to fulfill the comprehensive requirements of **MIT 8103: Advanced Database Systems**. The platform models a Nigerian digital financial technology company providing peer-to-peer money transfers, bill payments, airtime top-ups, and customer wallet management. QuickFund enforces strict multi-tier KYC identity verification, PCI-DSS card data security compliance, 10-digit NUBAN account numbering, and mathematically balanced double-entry bookkeeping.

Operating entirely on synthetic data, QuickFund uses the relational storage engine (PostgreSQL 18.6) as an active defense barrier that makes invalid financial states mathematically impossible at the schema level — not in application code. Across five progressive portfolio milestones, this project delivers a fully validated, production-grade database architecture that bridges classical relational theory with modern distributed and polyglot database paradigms.

### 1.1 Formal Organisation & Case Study Statement

| Required Dimension | Project Specification |
|:---|:---|
| **Organisation Name** | **QuickFund Digital Wallet & Financial Ledger System** |
| **Nature of Business** | Simulated Nigerian Fintech — Real-Time Digital Wallets, Peer-to-Peer Transfers, and Double-Entry Financial Ledger Platform |
| **Database Users** | 1. **Retail Customers:** Create wallets, deposit/withdraw funds, initiate transfers, view statements.<br>2. **Customer Support Staff:** Resolve account disputes and transaction issues.<br>3. **Compliance & Audit Officers:** Inspect immutable ledger lines, review KYC tiers, investigate fraud flags.<br>4. **System Microservices:** Process payments, emit notifications, generate reconciliation reports.<br>5. **Database Administrators:** Manage streaming replication, failover, partitioning, and cloud clusters. |
| **Major Data Stored** | Customer identities and multi-tier KYC verification records, 10-digit NUBAN wallet accounts and balances, immutable double-entry ledger entries (Debit/Credit), saved beneficiaries, PCI-DSS masked card tokens, fraud flags and risk scores, MongoDB KYC profile documents, and high-volume audit event streams. |
| **Key Operations Supported** | Atomic fund transfers with race-safe balance checks, balanced dual ledger entries ($\sum \text{Debits} = \sum \text{Credits}$), idempotent transfer retries via unique keys, compensating transaction reversals, analytical aggregation pipelines, partition pruning, and lag-aware distributed read routing. |

```
                    ┌──────────────────────────────────────────────────────────┐
                    │             Customer Mobile App / API Gateway            │
                    └────────────────────────────┬─────────────────────────────┘
                                                 │
                                                 ▼
                    ┌──────────────────────────────────────────────────────────┐
                    │               Connection Router (Write / Read)           │
                    └────────────────┬─────────────────────────────┬───────────┘
                                     │ Writes & post-transfer reads │ Analytical reads
                                     ▼                              ▼
      ┌──────────────────────────────────────────────────┐  ┌─────────────────────────────────────────────┐
      │        PostgreSQL 18.6 Primary (port 5433)       │  │    PostgreSQL 18.6 Replica (port 5434)      │
      │  - Authoritative System of Record for Money      │  │  - Hot Standby Streaming Replica            │
      │  - ACID Double-Entry Financial Transactions      │──│  - Account Statements & Audit Reports       │
      │  - Row-Level Locking (LEAST/GREATEST ordering)   │WAL│  - Replication Slot: replica1_slot          │
      └────────────────────────┬─────────────────────────┘  └─────────────────────────────────────────────┘
                               │
                               │ UUID customer_id link
                               ▼
      ┌──────────────────────────────────────────────────┐
      │        MongoDB Atlas Cloud Cluster               │
      │   - 3-Node Replica Set (AWS Paris, eu-west-3)   │
      │   - KYC Profile Documents (5,000 customers)     │
      │   - Audit Event Stream (100,000 events)          │
      │   - JSON Schema Validation (Error Code 121)      │
      │   - TTL Session Cleanup & Partial Fraud Index    │
      └──────────────────────────────────────────────────┘
```

---

## 2. Portfolio 1: Relational Schema Design, Normalisation, & Storage Engine Defense

### 2.1 Relational Architecture & Normalisation

The foundation of QuickFund rests on an eight-table relational schema, normalized through First Normal Form (1NF), Second Normal Form (2NF), Third Normal Form (3NF), and Boyce-Codd Normal Form (BCNF), with four justified deliberate trade-offs documented in `normalisation.md`:

1. **`customers`**: UUID-keyed customer profiles with unique email and phone constraints and classification enforcement (`INDIVIDUAL` / `MERCHANT`).
2. **`kyc_records`**: Multi-tier identity verification submissions with document references, review status state machines, and conditional timestamp enforcement.
3. **`accounts`**: 10-digit NUBAN-format wallet accounts with non-negative `NUMERIC(15,2)` balance enforcement.
4. **`beneficiaries`**: Saved recipient profiles with `ON DELETE CASCADE` from the parent customer.
5. **`cards`**: PCI-DSS compliant linked payment cards — storing only masked `last_four` digits and token hashes, never full card numbers.
6. **`transactions`**: High-durability financial event ledger with idempotency keys, positive amount checks, reversal self-reference, and type/status constraints.
7. **`ledger_entries`**: Append-only, immutable double-entry financial journal lines (Debit / Credit), with per-transaction direction uniqueness enforcement.
8. **`fraud_flags`**: Compliance and anomaly tracking with risk scores (0–100) bound to specific transactions.

### 2.2 Mathematical Invariants & Schema Defense

Rather than trusting application code to maintain financial integrity, QuickFund implements schema-level constraints that reject invalid states at the PostgreSQL engine level:

- **The Double-Entry Invariant:** Every completed transfer produces exactly two immutable ledger rows — one `DEBIT` and one `CREDIT` — where total debits equal total credits: $\sum \text{Debits} = \sum \text{Credits}$.
- **Monetary Precision:** All balances and transfer amounts are stored as exact `NUMERIC(15,2)` values with explicit `CHECK (amount > 0)`. Floating-point types (`FLOAT`, `REAL`, `DOUBLE PRECISION`) are explicitly prohibited.
- **Non-Negative Balance Enforcement:** `CHECK (balance >= 0.00)` on `accounts` makes overdrafts impossible without application intervention.
- **NUBAN Account Number Format:** `CHECK (account_number ~ '^[0-9]{10}$')` enforces exactly 10 numeric digits on every wallet.
- **PCI-DSS Card Masking:** `CHECK (last_four ~ '^[0-9]{4}$')` ensures the full PAN can never be persisted in the database.
- **Single Reversal Invariant:** A `REVERSAL` transaction must reference an original transaction (`reversal_of IS NOT NULL`), while other transaction types must not. This prevents duplicate refund exploits at the constraint level.
- **KYC Conditional Timestamp:** A `CHECK` constraint enforces that `verified_at IS NULL` when `status = 'PENDING'` and `verified_at IS NOT NULL` when `APPROVED` or `REJECTED`.
- **Ledger Direction Uniqueness:** A unique constraint on `(transaction_id, account_id, entry_direction)` prevents an account from appearing twice in the same direction within a single transaction.

### 2.3 Seed Data & Constraint Validation Results

The seed data generator (`Balogun_Toluwalase_301872815_seed_data.sql`) uses a single-transaction set-based approach with `generate_series()` and cross joins — no procedural loops — to produce:

| Table | Row Count |
|:---|:---|
| `customers` | 5,001 |
| `accounts` | 6,001 |
| `transactions` | 206,101 |
| `ledger_entries` | 412,201 |

An automated PL/pgSQL assertion suite (`Balogun_Toluwalase_301872815_constraint_tests.sql`) validated 15 boundary conditions, negative violations, and cascade behaviours. **All 15 of 15 assertions passed**, confirming zero unhandled constraint violations, correct double-entry balance, and proper `ON DELETE CASCADE` / `ON DELETE RESTRICT` behaviour.

---

## 3. Portfolio 2: Query Processing Engine, Cost-Based Optimization, & Index Design

### 3.1 Cost-Based Query Optimization

Portfolio 2 evaluated PostgreSQL's Cost-Based Optimizer (CBO) across 11 mission-critical access patterns on a live 629,304-row dataset, analyzing plan nodes via `EXPLAIN (ANALYZE, BUFFERS)` to observe planner costs, shared buffer page accesses, sort spill behaviour, and actual execution latencies.

**Workload Scale at time of testing:**

| Table | Rows | Heap Size | Total with Indexes |
|:---|:---|:---|:---|
| `ledger_entries` | 412,201 | 40 MB | 129 MB (60.8% of DB) |
| `transactions` | 206,101 | 31 MB | 79 MB (37.3% of DB) |
| `accounts` | 6,001 | 1.6 MB | 2.6 MB |
| `customers` | 5,001 | 656 kB | 1.5 MB |

### 3.2 Index Engineering Strategy

A naive approach of indexing every column degrades write performance through index maintenance overhead and WAL amplification. QuickFund designed seven highly targeted indexes:

1. **`idx_ledger_entries_account_created_at_desc`** — `(account_id, created_at DESC)`: Satisfies the equality-then-range rule for account statement queries, allowing pre-sorted rows to be fetched directly from B-Tree leaf nodes without in-memory Sort operations.
2. **`idx_accounts_customer_id`** — `(customer_id)`: Eliminates nested-loop foreign key scans on customer-to-account joins.
3. **`idx_transactions_transfers_completed_time`** — `(completed_at DESC) INCLUDE (amount) WHERE type='TRANSFER' AND status='SUCCESS'`: A partial covering index making `completed_at` and `amount` queryable without touching the heap.
4. **`idx_ledger_entries_debit_covering`** — `(transaction_id, account_id) WHERE entry_direction='DEBIT'`: Partial covering index serving reconciliation queries against only the debit side of journal entries.
5. **`idx_transactions_type_time_covering`** — `(transaction_type, created_at DESC) INCLUDE (status, amount)`: Covering index for type-partitioned analytics.
6. **`idx_transactions_failed_recent`** — `(created_at DESC) INCLUDE (amount) WHERE status='FAILED'`: Partial index for operations triage queues, covering only the minority of failed transactions.
7. **`idx_transactions_success_monthly`** — `(created_at DESC) INCLUDE (transaction_type, amount) WHERE status='SUCCESS'`: Covering index for monthly reporting aggregations.

### 3.3 Empirical Benchmark Results

| Query | Metric | Before | After | Improvement |
|:---|:---|:---|:---|:---|
| **Q1** Account statement | Execution time | 22.80 ms (baseline) / 155.31 ms (unindexed) | **1.51 ms** | **102.8× speedup** |
| **Q1** Account statement | Buffer pages hit | 24,294 | 413 | **98.3% I/O reduction** |
| **Q2** Completed transfer totals | Execution time | 148.49 ms | **0.124 ms** | **1,197× speedup** |
| **Q2** Completed transfer totals | Buffer pages | 4,036 | 3 | 100% Index Only Scan |
| **Q8** Net movement sort | Disk spill | 6,464 kB external merge | **0 kB** | Fully in-memory |
| **Q11** Monthly volume sort | Disk spill | 6,880 kB external merge | **0 kB** | Fully in-memory |

The PostgreSQL planner's behaviour was also empirically verified: by toggling `enable_seqscan`, the planner's 4:1 `random_page_cost` to `seq_page_cost` ratio was confirmed to govern the crossover point between Index Scans and Sequential Scans as table selectivity changes — directly observable through planner plan node switching.

---

## 4. Portfolio 3: Transaction Processing, ACID Boundaries, & Concurrency Control

### 4.1 Atomic Financial Transfer Lifecycle

A financial transfer in QuickFund cannot be implemented as isolated SQL statements. The PL/pgSQL function `transfer_funds()` encapsulates every transfer inside a single ACID transaction boundary that executes as an indivisible unit:

1. Idempotency key lookup — if the key already exists, return the existing transaction ID without re-executing.
2. Pessimistic row-level lock acquisition on both source and destination accounts in deterministic order.
3. Balance solvency check — read sender balance **after** acquiring the lock, not before.
4. Debit the sender account and credit the recipient account atomically.
5. Insert the durable `transactions` row with `status = 'SUCCESS'`.
6. Insert two balanced `ledger_entries` rows: one `DEBIT` on the sender, one `CREDIT` on the recipient.
7. Atomic `COMMIT`. If any step raises an exception (insufficient funds, constraint violation, system error), the engine rolls back all modifications with zero partial state.

### 4.2 Deadlock Elimination via Deterministic Lock Ordering

When concurrent sessions transfer funds between Account A → B and Account B → A simultaneously, unordered row locking creates a circular wait graph (deadlock). QuickFund eliminates this mathematically by enforcing a global lock acquisition order:

$$v\_\text{first} = \text{LEAST}(v\_\text{from\_id},\; v\_\text{to\_id}), \quad v\_\text{second} = \text{GREATEST}(v\_\text{from\_id},\; v\_\text{to\_id})$$

Because all concurrent sessions acquire row locks in identical ascending UUID order, circular wait graphs are structurally impossible — the system is deadlock-immune by construction, not by retry policy.

The deliberate `transfer_funds_unordered()` function was built as a contrast: it locks the sender first, then sleeps 10 ms (`pg_sleep(0.01)`), then locks the receiver, exposing the race window that causes deadlocks.

### 4.3 Isolation Level Analysis & Concurrency Benchmarking

| Isolation Level | Observed Behaviour |
|:---|:---|
| **`READ COMMITTED`** (default) | Non-repeatable read confirmed: Session 1 observed a balance change committed by Session 2 in a subsequent read within the same transaction (`balance 500.00 → 400.00`). |
| **`REPEATABLE READ`** | Serialization failure confirmed: Session 1 attempted `UPDATE` on a row modified and committed by Session 2; PostgreSQL aborted Session 1 with `ERROR: could not serialize access due to concurrent update (SQLSTATE 40001)`. First-committer-wins semantics verified. |
| **Deadlock Detection** | Circular wait confirmed without ordered locking: Session 1 (PID 12856) locked account A, Session 2 (PID 35752) locked account B, then each attempted to acquire the other's lock. PostgreSQL's deadlock detector terminated PID 35752 with `ERROR: deadlock detected`. |

**Concurrency Stress Test (`pgbench`):**
- 10 concurrent clients, 4 worker threads, 200 transactions per client, contending over 20 hot accounts
- **Ordered locking result:** 0 deadlocks (0.00% aborts), system balance invariant preserved at exactly ₦10,000,000,000.00 across all runs
- **Unordered locking result:** Immediate cascading deadlock aborts, process 35752 terminated

**Financial Integrity Verification (post-stress):**

| Invariant Check | Result |
|:---|:---|
| `total_money_in_system` | ₦10,000,000,000.00 (unchanged) |
| `unbalanced_transactions` ($\sum D \neq \sum C$) | 0 |
| `mismatched_accounts` (balance ≠ net ledger) | 0 |
| `stuck_pending_transactions` | 0 |

**Own Experiment — Safe Transaction Reversal (`reverse_transfer()`):**
A tested `reverse_transfer()` function executed a compensating reversal on a completed transfer (`e441be5a-12ba-42eb-bc52-2b9bb075b996`, amount ₦5.00). The function: flipped the debit and credit directions, marked the original as `REVERSED`, created a linked `REVERSAL` transaction, and blocked a second reversal attempt on the same transaction with `ERROR: NOT_REVERSIBLE: only a SUCCESS transfer can be reversed (status is REVERSED)`. Post-reversal net ledger balance for both transactions summed to exactly `0.00`.

---

## 5. Portfolio 4: Polyglot Persistence, NoSQL Document Store, & Operational Event Streams

### 5.1 Polyglot Architectural Rationale

Financial ledgers demand ACID relational guarantees, but QuickFund also generates high-volume semi-structured data that does not fit cleanly into relational rows. This impedance mismatch is resolved through **Polyglot Persistence**:

| Data Domain | Storage System | Reason |
|:---|:---|:---|
| Wallets, balances, transfers, ledger | **PostgreSQL** | Requires strict ACID, row-level locks, `NUMERIC(15,2)` precision, foreign key constraints, and double-entry invariants |
| KYC identity profiles (5,000) | **MongoDB `kyc_profiles`** | Polymorphic documents — BVN has `verified_with` field, Passport has `expiry` and `issuing_country`, NIN has different fields; forcing these into SQL creates wide sparse null-heavy tables |
| Audit events (100,000) | **MongoDB `audit_events`** | High-velocity append-only stream with varied payload structures per event type; new event types require no DDL migrations |
| Login sessions | **MongoDB `login_sessions`** | Ephemeral auth tokens that expire; ideal for MongoDB's built-in TTL index auto-purge |

The `customer_id` field in MongoDB stores the exact UUID text from PostgreSQL's `customers.customer_id`, creating a cross-system link. Because PostgreSQL and MongoDB are independent engines, there is no native foreign key enforcement across them — data lifecycle consistency must be coordinated at the application layer.

### 5.2 Strict Schema Validation & Indexing

MongoDB JSON Schema Validation was implemented on all three collections (`validationAction: "error"`, `validationLevel: "strict"`). An attempted insertion of `{ customer_id: 'not-a-uuid', status: 'MAYBE' }` was rejected by the engine with **`DocumentValidationFailure (code 121)`**.

Validation rules enforced:
- `customer_id` must match the UUID regex `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`
- `status` restricted to enum `['PENDING', 'VERIFIED', 'REJECTED']`
- `tier` restricted to integers 1–3
- `documents` array must contain at least one item with `type` restricted to `['BVN', 'NIN', 'PASSPORT', 'DRIVERS_LICENCE', 'UTILITY_BILL']`

**Seeded dataset:** 5,000 KYC profiles (tier 1: 2,741 / tier 2: 1,660 / tier 3: 599) and 100,000 audit events.

**Index benchmarks:**

| Query | Before Index | After Index | Improvement |
|:---|:---|:---|:---|
| Latest 20 events for one customer | SORT → COLLSCAN, 100,000 docs, **63 ms** | LIMIT → FETCH → IXSCAN, 20 docs, **1 ms** | 63× faster |
| `FRAUD_FLAG` events, last 7 days | COLLSCAN, 100,000 docs, **60 ms** | FETCH → IXSCAN, 373 docs, **2 ms** | 30× faster |
| KYC profile for one customer | COLLSCAN, 5,000 docs, **6 ms** | EXPRESS_IXSCAN, 1 doc, **1 ms** | 6× faster |

**Own Work — Custom Partial Fraud Index (`idx_audit_fraud_partial`):**

A partial index on `audit_events` filtered only to `FRAUD_FLAG` events (approximately 5% of the collection):

```javascript
nosql.audit_events.createIndex(
  { ts: -1 },
  { name: 'idx_audit_fraud_partial', partialFilterExpression: { event_type: 'FRAUD_FLAG' } }
);
```

| Metric | Full Index (`idx_audit_type_ts`) | Partial Index (`idx_audit_fraud_partial`) |
|:---|:---|:---|
| Index size | 1,112 KB | **72 KB** |
| Fraud query latency | 14 ms | **1 ms** |
| Space saving | — | **93.5% reduction** |

The partial index covered only 5,024 documents (5.0% of 100,000), making it dramatically smaller than the full type index while achieving the same or better query latency for fraud-specific analytics.

---

## 6. Portfolio 5: Distributed Systems, High Availability, Partitioning, & Cloud Topologies

### 6.1 Multi-Node Streaming Replication Topology

Portfolio 5 provisioned a distributed multi-node architecture using Docker Compose:

- **`quickfund-pg-primary` (port 5433):** PostgreSQL 18.6 primary — read-write authoritative node with WAL-level `replica`, physical replication slot `replica1_slot`, and 10 max WAL senders.
- **`quickfund-pg-replica` (port 5434):** PostgreSQL 18.6 hot standby — continuously streaming and applying WAL records, enforcing read-only access.

The full QuickFund dataset (206,109 transactions, 412,217 ledger entries) was restored to the Docker primary via `pg_dump` / `psql` and verified against row counts.

**Primary health verified:**
- `is_replica = f` (primary read-write node)
- `state = streaming`, `sync_state = async`
- Replication slot `replica1_slot` `active = t`

**Replica read-only enforcement confirmed:** A direct `UPDATE` on the standby was rejected with:
```
ERROR: cannot execute UPDATE in a read-only transaction
```

### 6.2 Empirical CAP Theorem Live Demonstrations

**1. Stale Read Simulation (Asynchronous Replication Lag):**

WAL replay was deliberately paused on the standby. While paused:
- Primary `replication_marker` count: **2**
- Replica `replication_marker` count: **1**
- Primary `sent_lsn`: `0/DB73268` | Replica `replay_lsn`: `0/DB73160` | `caught_up = false`

This proved that an asynchronous replica can serve stale data during replay lag — a real double-spend risk in a payments platform where a customer could see a pre-transfer balance and re-initiate a payment. Upon resuming replay: both LSNs advanced to `0/DB73370` and `caught_up = true`.

**2. Synchronous Replication & The Availability Sacrifice:**

With `synchronous_commit = on` and `synchronous_standby_names = 'replica1'` configured (`sync_state` confirmed as `sync`), stopping the replica caused the primary to **hang indefinitely** on a write commit. Interrupting with Ctrl+C produced:

```
WARNING: canceling wait for synchronous replication due to user request
DETAIL: The transaction has already committed locally, but might not have been replicated to the standby.
```

This provided live empirical proof of the CAP theorem: under a network partition, guaranteeing strict consistency (C) forces the system to sacrifice availability (A).

### 6.3 Horizontal Scale via Declarative Hash Partitioning

The `ledger_entries` table (412,217 rows) was re-architected into 4 declarative hash partitions on `account_id`:

| Partition | Row Count |
|:---|:---|
| `ledger_shard_0` | 111,749 |
| `ledger_shard_1` | 99,844 |
| `ledger_shard_2` | 99,123 |
| `ledger_shard_3` | 101,501 |
| **Total** | **412,217 (100% data fidelity)** |

**Partition Pruning Results:**
- Query with `WHERE account_id = <uuid>`: Scanned **1 partition** via Index Seek — 75% I/O reduction
- Query with `WHERE transaction_id = <uuid>`: Triggered Parallel Append across **all 4 partitions** (no pruning on a non-shard-key column)

**Cross-Shard Complexity Analysis:**
- Transactions touching exactly 1 shard: 51,269
- Transactions touching 2 shards (cross-shard): 154,840 (**75.1% of all 206,109 transactions**)

This confirmed that `account_id` is an effective shard key for OLTP balance lookups, but that 75% of transfers span multiple shards — a real design challenge for distributed atomic consistency.

### 6.4 Manual Failover & Split-Brain

**Failover timeline:**
- Primary stopped at: `2026-11-11 03:29:27 UTC`
- Promoted replica first accepted a write at: `2026-11-11 03:31:10 UTC`
- **Measured RTO: approximately 103 seconds (~1.7 minutes)**

**Sequence ID jump (5 → 38):** PostgreSQL pre-allocates sequence cache blocks of 32 values in memory. When the primary crashed, its cached block was lost. The promoted replica resumed from cache block boundary 38 — confirming that application code must never assume sequence continuity.

**Split-Brain:** When the old primary was restarted alongside the promoted replica, both reported `is_replica = f`. This demonstrates why manual failover without automated fencing (STONITH) is dangerous in production — both nodes would accept writes, creating diverging ledger states that cannot be automatically merged.

### 6.5 Cloud Deployment: MongoDB Atlas (Experiment 6)

**Atlas cluster topology:**
- Cluster: `atlas-5uum6d-shard-0` — 3 nodes, MongoDB 8.0.37, **AWS Paris (`eu-west-3`)**
- Primary: `ac-u5vzxxk-shard-00-02.z21r9ec.mongodb.net:27017`
- Secondaries: `ac-u5vzxxk-shard-00-00`, `ac-u5vzxxk-shard-00-01`

**Write concern latency (100 sequential inserts each):**

| Run | Write Concern | Total Time | Per-Insert Latency |
|:---|:---|:---|:---|
| Run 1 | `w: 1` (Primary only) | 22,252 ms | **222.5 ms** |
| Run 2 | `w: majority` (Quorum) | 22,741 ms | **227.4 ms** |
| Run 3 | `w: 1` (control repeat) | 21,790 ms | **217.9 ms** |

**Key finding:** The 4.9 ms difference between `w: 1` and `w: majority` is completely within random network jitter (the two `w: 1` runs differed by 4.6 ms). The ~220 ms WAN round-trip from Nigeria/Europe to AWS Paris dominated 98%+ of the total latency. Internal Atlas replication between nodes on sub-millisecond datacenter fiber cost less than 2–3 ms. In cloud deployments, `w: majority` provides complete crash durability and zero-data-loss protection with virtually zero observable performance penalty.

---

## 7. Comprehensive Portfolio Evaluation & Quantitative Metrics

| Portfolio Milestone | Core Technology | Primary Pattern | Key Verified Metric |
|:---|:---|:---|:---|
| **Portfolio 1: Database Design** | PostgreSQL 18.6 | Relational 3NF/BCNF, Double-Entry Invariants | 5,001 customers · 412,201 ledger lines · 15/15 constraint tests passed · zero negative balances |
| **Portfolio 2: Query Optimisation** | PostgreSQL 18.6 CBO | B-Tree, Partial, Covering Indexes | Q1: 102.8× speedup · Q2: 1,197× speedup · 6.9 MB disk spill eliminated · 98.3% I/O reduction |
| **Portfolio 3: Transactions & Concurrency** | PostgreSQL ACID + pgbench | Deterministic Lock Ordering (LEAST/GREATEST) | 10 clients · 2,000 txns · 20 hot accounts · 0 deadlocks · ₦10,000,000,000.00 invariant preserved |
| **Portfolio 4: NoSQL Modelling** | MongoDB 8.0 / Atlas | Polyglot Persistence, Schema Validation | 5,000 KYC profiles · 100,000 audit events · COLLSCAN 63 ms → IXSCAN 1 ms · 93.5% partial index size reduction |
| **Portfolio 5: Distributed Systems** | Docker + PostgreSQL 18.6 + Atlas | Physical Streaming Replication, Hash Sharding | 4 shards · 412,217 rows · RTO 103 s · stale read LSN divergence captured · w:majority ≈ w:1 over 220 ms WAN |

---

## 8. Production Limitations & Future Engineering Roadmap

While QuickFund provides an enterprise-grade academic foundation, transitioning to hyperscale production requires addressing several real-world limitations:

1. **Distributed Two-Phase Commit (2PC) Across Shards:** The current hash partitioning models single-node horizontal scaling. True cross-node sharding for atomic transfers across shard boundaries requires distributed transaction coordinators (Citus, CockroachDB, or Google Spanner) using Paxos or Raft consensus.

2. **Automated Quorum Failover:** The demonstrated failover required 103 seconds of manual CLI execution. Production deployment requires automated consensus-driven failover tools (Patroni backed by etcd or Consul) with STONITH fencing to guarantee split-brain-free failover in under 10 seconds.

3. **Cross-System Referential Integrity:** The `customer_id` UUID link between PostgreSQL and MongoDB has no native enforcement. Orphaned MongoDB documents result when PostgreSQL customers are deleted without coordinated cleanup. A production platform requires event-driven lifecycle orchestration (Kafka/RabbitMQ CDC events, soft-delete patterns).

4. **Continuous WAL Archiving & PITR:** Physical streaming replication protects against primary server crash but cannot recover from logical errors (accidental `DROP TABLE`). Production requires WAL-G or pgBackRest continuous archiving to object storage with point-in-time recovery.

5. **Active-Active Multi-Region Replication:** As QuickFund expands across West Africa, single-primary architectures introduce cross-continental latency. CRDTs or globally distributed Spanner-style TrueTime concurrency models represent the next architectural tier.

6. **In-Transit Encryption:** Docker internal network communication operated without TLS mutual authentication in this portfolio. Production demands end-to-end mTLS on all database connections and VPC peering for MongoDB Atlas.

---

## 9. Individual Technical Reflection

### 9.1 Key Architectural Design Choices

**Engine-Level Defense vs. Application Logic:** In financial systems, application code is transient, bugs are inevitable, and race conditions are hard to predict. Embedding constraints directly into the PostgreSQL storage engine — `CHECK` constraints, unique partial indexes, `NOT NULL`, `ON DELETE RESTRICT` — guarantees mathematical consistency regardless of what client code attempts. An invalid ledger state is not just rejected; it is structurally impossible.

**Immutable Append-Only Ledger over Mutable Balances:** The `ledger_entries` table is never updated or deleted. Every monetary movement creates new rows. This means every balance can be verified mathematically from the entire history of debits and credits — a requirement for financial auditing. `accounts.balance` is a cached projection of that ledger, not the source of truth.

**Deterministic Concurrency over Optimistic Retries:** Under high-velocity concurrent transfers, optimistic concurrency control leads to high abort and retry rates under contention. Enforcing the `LEAST`/`GREATEST` lock ordering in PL/pgSQL eliminates the deadlock condition entirely without requiring any application-level retry logic or exponential backoff.

**Polyglot Separation by Data Characteristics:** Choosing which database to use for each data domain was not arbitrary. PostgreSQL was chosen for money because it must be right every time, by law. MongoDB was chosen for KYC documents and audit events because their schema variability and insertion velocity make relational tables the wrong tool.

### 9.2 Technical Challenges Faced & Engineering Solutions

**Deadlock Storms under High Concurrency:** During initial Portfolio 3 testing, running concurrent transfers without ordered locking caused immediate and cascading deadlock aborts. By enforcing `LEAST`/`GREATEST` UUID lock ordering in the PL/pgSQL function, all deadlocks were eliminated without reducing throughput between unrelated account pairs.

**External Disk Spills on Analytical Queries:** Sorting 412,000 ledger rows exceeded the 4 MB `work_mem` budget, spilling 6.5–6.9 MB to temporary disk files (`external merge Disk: 6464kB`). The solution was designing indexes with the sort order pre-embedded (`account_id, created_at DESC`), enabling the planner to stream pre-ordered rows directly from B-Tree leaf nodes without any in-memory or on-disk sort phase.

**Synchronous Replication Availability Hazard:** Setting `synchronous_standby_names` with a single replica created a situation where stopping that one replica froze the entire primary indefinitely. This proved that 2-node synchronous replication is not suitable for production. The solution design is a 3-node quorum (`FIRST 1 (replica_zone_a, replica_zone_b)`) where the primary commits as soon as any one of two replicas acknowledges, tolerating single-node failures with zero downtime and RPO = 0.

**MongoDB UUID Seed Data Mismatch:** The first version of the Portfolio 4 seed data script generated random UUIDs inside MongoDB documents instead of the actual PostgreSQL customer UUIDs. This caused `$lookup` aggregation joins to return zero results. The bug was identified by spot-checking a `customer_id` from `audit_events` against the exported `customer_ids.js` file and seeing no match. The fix was ensuring the seed script correctly reads from the exported UUID list.

### 9.3 Key Lessons Learned

**Database Performance is about Page Access, not Raw Speed:** Every dramatic speedup in Portfolio 2 came from reducing the number of 8 kB buffer pages the engine needed to touch — not from faster hardware. Cutting Q1 from 24,294 buffer hits to 413 is a 98.3% reduction in work, which is why the latency dropped by 102.8×.

**Eventual Consistency is a Financial Risk, not a Theory:** Watching the stale read during Portfolio 5 — where the replica confidently returned an old balance while the primary had already processed the transfer — made the distributed systems risk concrete. Reading from an asynchronous replica after a money transfer is not just technically incorrect; it is a customer-facing double-spend hazard.

**Network Topology Dominates Latency in Cloud Systems:** The write concern benchmark showed that `w: majority` added less than 5 ms over `w: 1` because Atlas internal replication between nodes in the same Paris datacenter costs under 2 ms. The 220 ms I observed was my internet connection to Paris, not the database. This changes how distributed systems should be evaluated: measure the right thing.

---

## 10. Academic Integrity & AI Assistance Declaration

In compliance with Miva Open University guidelines, the Antigravity IDE's AI agent was used as an interactive coding companion throughout this project.

**What the AI was used for:** Structuring the set-based seed data generator using `generate_series()`; explaining `external merge Disk` spill output in EXPLAIN ANALYZE; helping draft the syntax of the `reverse_transfer()` PL/pgSQL function; adapting MongoDB seed scripts to use real PostgreSQL customer UUIDs; explaining Docker networking errors during replication setup; drafting the partitioning and write concern benchmark scripts.

**How output was verified:** Every script was executed personally on my own PostgreSQL 18.6 database and MongoDB Atlas cluster. All output files in `output/` directories and all screenshots were captured personally during those runs. The AI produced at least one error I had to identify and fix myself (seed data generating random rather than real UUIDs, causing `$lookup` joins to return zero results). All analysis, reflection, and README explanations were written by me after running the experiments.

Full disclosure is provided in [`Balogun_Toluwalase_AI_Use_Declaration.md`](Balogun_Toluwalase_AI_Use_Declaration.md).

**Use of AI tools does not remove my responsibility for the accuracy, originality, and understanding of this work.**

---

## 11. Key Academic & Regulatory References

- **Codd, E. F. (1970).** A Relational Model of Data for Large Shared Data Banks. *Communications of the ACM*, 13(6), 377–387.
- **Gray, J., & Reuter, A. (1993).** *Transaction Processing: Concepts and Techniques*. Morgan Kaufmann.
- **Brewer, E. A. (2000).** Towards Robust Distributed Systems. *ACM PODC Keynote*.
- **Kleppmann, M. (2017).** *Designing Data-Intensive Applications: The Big Ideas Behind Reliable, Scalable, and Maintainable Systems*. O'Reilly Media.
- **PostgreSQL Global Development Group. (2024).** *PostgreSQL 18.6 Documentation: Concurrency Control, The Query Planner, and High Availability & Streaming Replication*. https://www.postgresql.org/docs/
- **MongoDB, Inc. (2024).** *MongoDB Manual (v8.0): Aggregation Pipelines, Document Modeling, Replica Set Write Concern, and Schema Validation*. https://www.mongodb.com/docs/manual/
- **Central Bank of Nigeria (CBN). (2020).** *Regulatory Framework for the Bank Verification Number (BVN) Operations and Electronic Payments in Nigeria*. Applied for KYC tier structure and 10-digit NUBAN account number standards.
- **PCI Security Standards Council. (2022).** *Payment Card Industry Data Security Standard (PCI DSS) v4.0*. Applied for Primary Account Number masking in the `cards` entity.
- *(Full bibliography containing 20 authoritative citations available in [`Balogun_Toluwalase_301872815_References.md`](Balogun_Toluwalase_301872815_References.md)).*

---

## 12. Conclusion

The QuickFund portfolio represents a comprehensive, methodically engineered implementation of modern database systems theory applied to a realistic Nigerian fintech context. By combining strict relational mathematical invariants across 412,201 immutable ledger lines, meticulous query plan tuning achieving up to 1,197× speedup, deterministic concurrency controls eliminating all deadlocks across 2,000 concurrent transactions, polyglot document persistence with 93.5% partial index storage savings, and distributed streaming replication with live CAP theorem demonstrations, QuickFund demonstrates that financial software reliability is fundamentally a database engineering discipline.

The numbers in this report are not estimates — they were measured, observed, and verified personally across a live PostgreSQL 18.6 cluster and MongoDB Atlas deployment. Every claim in this document is backed by output files and screenshots in the repository.

All schemas, test suites, performance benchmarks, and deployment configurations are fully version-controlled, reproducible, and verifiable in the project repository.

---

**Report Authored and Certified by:**
**Balogun Toluwalase (Student ID: 301872815)**
Master of Information Technology Candidate, Miva Open University
November 12, 2026

