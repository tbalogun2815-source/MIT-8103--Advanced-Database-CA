# Portfolio 3: Concurrency, Transactions & ACID Analysis

## Environment
* **Database Engine**: PostgreSQL 18.6 on x86_64-windows (MSVC 64-bit) (source: `screenshots/06_exp3a_read_committed.png`, `portfolio-2-query-optimisation/performance_analysis.md`).
* **Database Name**: `quickfund_db`.
* **Baseline Table Row Counts** (source: `screenshots/psql counts check.png` and `screenshots/PGADMIN graphical counts check.png`):
  * `accounts`: 6,001
  * `transactions`: 206,101
  * `ledger_entries`: 412,201
  * `customers`: 5,001 (source: `portfolio-2-query-optimisation/performance_analysis.md`).

---

## The transfer function
The function `transfer_funds()` in `01_transfer_function.sql` performs money movement between two accounts as a single atomic unit.

* **Idempotency**: Inserts into `transactions` with `ON CONFLICT (idempotency_key) DO NOTHING`. If the key already exists, returns the existing `transaction_id` without executing transfers.
* **Deadlock Prevention (Ordered Locking)**: Enforces `v_first_id := LEAST(v_from_id, v_to_id)` and `v_second_id := GREATEST(v_from_id, v_to_id)` before calling `PERFORM ... FOR UPDATE`. Because all sessions lock accounts in the same UUID order, mutual circular wait is prevented.
* **Race-Safe Balance Check**: Reads sender `balance` only after acquiring the row lock, ensuring concurrent transactions cannot bypass the `v_from_bal < p_amount` check.
* **Double-Entry Ledger**: Inserts one `DEBIT` and one `CREDIT` row into `ledger_entries` using `clock_timestamp()` for real-time chronological ordering.
* **Unordered Flaw Function**: `transfer_funds_unordered()` locks sender first, sleeps 0.01s (`pg_sleep(0.01)`), and locks receiver second, deliberately exposing the race condition that causes deadlocks.

---

## Commit and rollback
All numbers and output below come directly from `portfolio-3-transactions-concurrency/output/03_commit_rollback_output.txt`:

* **Test Accounts Used**:
  * Sender account: `2000000955`
  * Receiver account: `2000000992`
* **Starting Balances**:
  * Account `2000000955`: `162341.84` NGN
  * Account `2000000992`: `162293.45` NGN

### Demo 1: COMMIT (Permanent Persistence)
* Transferred: `100.00` NGN
* Returned `transaction_id`: `76c18356-d32c-4672-a6c0-95779ac19815`
* Inside transaction balances: `2000000955` = `162241.84`, `2000000992` = `162393.45`
* Post-COMMIT balances: `2000000955` = `162241.84`, `2000000992` = `162393.45`
* *Explanation*: The balance changes and ledger entries become permanent and visible to all other sessions upon `COMMIT`.

### Demo 2: ROLLBACK (Reversion)
* Transferred: `100.00` NGN
* Returned `transaction_id`: `31bf0813-f4d2-4003-bd85-235e360f8ad7`
* Inside transaction balances: `2000000955` = `162141.84`, `2000000992` = `162493.45`
* Post-ROLLBACK balances: `2000000955` = `162241.84`, `2000000992` = `162393.45`
* Query `count(*) FROM transactions WHERE idempotency_key = :'k'`: `0`
* *Explanation*: `ROLLBACK` completely discards uncommitted in-flight modifications; no database record remains.

### Demo 3: Automatic Rollback on Business Violation
* Attempted Transfer: `999999999.00` NGN
* Error Raised: `psql:portfolio-3-transactions-concurrency/03_commit_rollback_demo.sql:59: ERROR: INSUFFICIENT_FUNDS: balance 162241.84 is less than 999999999.00`
* Balances: untouched at `162241.84` and `162393.45`
* Query `count(*) FROM transactions WHERE idempotency_key = 'demo-too-big'`: `0`
* *Explanation*: The PL/pgSQL function raises an exception, aborting the transaction block and preventing partial updates.

### Demo 4: Idempotency Verification
* Transfer Amount: `25.00` NGN
* First call returned `transaction_id`: `bbdd9ba4-f042-4ac1-9d69-78e5e6b298d3`
* Retry call with same key returned: `bbdd9ba4-f042-4ac1-9d69-78e5e6b298d3`
* Query `count(*) FROM transactions WHERE idempotency_key = :'k'`: `1`
* Post-transfer balances: `2000000955` = `162216.84`, `2000000992` = `162418.45`
* *Explanation*: The identical key was recognized; the second call returned the original ID without charging the sender twice.

### Demo 5: SAVEPOINT (Partial Rollback)
* Step 1: Transferred `10.00` NGN, returned `first_transfer` = `43bd07bb-7b4b-4588-a042-c78cf5b19f4e`
* Step 2: Set `SAVEPOINT before_second_transfer`
* Step 3: Attempted `999999999.00` transfer; failed with `INSUFFICIENT_FUNDS: balance 162206.84 is less than 999999999.00`
* Step 4: Executed `ROLLBACK TO SAVEPOINT before_second_transfer` followed by `COMMIT`
* Final Balances: `2000000955` = `162206.84`, `2000000992` = `162428.45`
* *Explanation*: Rolling back to a savepoint discards only the failed sub-operation while retaining earlier valid operations in the transaction.

### Double-Entry Ledger Lines
* Top 8 rows from `ledger_entries` in `output/03_commit_rollback_output.txt`:
  * `43bd07bb-7b4b-4588-a042-c78cf5b19f4e` | `2000000992` | `CREDIT` | `10.00`
  * `43bd07bb-7b4b-4588-a042-c78cf5b19f4e` | `2000000955` | `DEBIT`  | `10.00`
  * `bbdd9ba4-f042-4ac1-9d69-78e5e6b298d3` | `2000000992` | `CREDIT` | `25.00`
  * `bbdd9ba4-f042-4ac1-9d69-78e5e6b298d3` | `2000000955` | `DEBIT`  | `25.00`
  * `76c18356-d32c-4672-a6c0-95779ac19815` | `2000000992` | `CREDIT` | `100.00`
  * `76c18356-d32c-4672-a6c0-95779ac19815` | `2000000955` | `DEBIT`  | `100.00`
  * `5d6dfbb7-2896-4254-95bf-cb79f60fd92c` | `2000000992` | `CREDIT` | `10.00`
  * `5d6dfbb7-2896-4254-95bf-cb79f60fd92c` | `2000000955` | `DEBIT`  | `10.00`

---

## align Experiments with screenshots

### Experiment 1: Transaction Baseline and Function Verification
* `screenshots/psql counts check.png` & `screenshots/PGADMIN graphical counts check.png`: Baseline checks showing 6,001 accounts, 206,101 transactions, and 412,201 ledger lines.
* `screenshots/Test transfer function.png`: Verifying active account records and initial balances in pgAdmin 4.
* `screenshots/commit rollback output .png`: PowerShell command executing `03_commit_rollback_demo.sql` redirecting into `output/03_commit_rollback_output.txt`.

### Experiment 2: Row-Level Locking and Wait States
* `screenshots/04_exp2_waiting.png`: Session 1 acquires lock via `SELECT balance FROM accounts WHERE account_number = '9000000001' FOR UPDATE;`. Session 2 issues update on the same row and blocks.
* `screenshots/exp2_unblocked.png`: Query on `pg_stat_activity` identifies Session 2:
  * `pid`: `21060`
  * `state`: `active`
  * `wait_event_type`: `Lock`
  * `wait_event`: `transactionid`
  * `query`: `SELECT balance FROM accounts WHERE account_number...`
  * *Explanation*: Session 2 is held in PostgreSQL's lock manager waiting for Session 1's transaction ID to finish. Once Session 1 commits/rolls back, Session 2 unblocks immediately.

### Experiment 3a: Read Committed Isolation
* `screenshots/06_exp3a_read_committed.png`: In default `READ COMMITTED`, Session 1 queries Alice (`9000000001`). Session 2 updates balance by deducting 100 (`UPDATE accounts SET balance = balance - 100 WHERE account_number = '9000000001'`) and commits. Subsequent read in Session 1 observes new balance `400.00`.
* *Explanation*: Demonstrates non-repeatable reads allowed under statement-level snapshot isolation.

### Experiment 3b: Repeatable Read Isolation
* `screenshots/07_exp3b_repeatable_read.png`: Session 1 runs under `REPEATABLE READ` and reads balance `500.00`. Session 2 modifies the row and commits. When Session 1 attempts `UPDATE accounts SET balance = balance - 50 WHERE account_number = '9000000001'`, PostgreSQL aborts Session 1 with:
  `ERROR: could not serialize access due to concurrent update`.
* *Explanation*: PostgreSQL applies first-committer-wins rule to prevent lost updates under snapshot isolation.

### Experiment 4: Deadlock Detection
* `screenshots/08_exp4_deadlock.png`: Cross-transfer without ordered locking:
  * Session 1 updates Bob (`9000000002`), then attempts to update Alice (`9000000001`).
  * Session 2 updates Alice (`9000000001`), then attempts to update Bob (`9000000002`).
  * Result: `ERROR: deadlock detected`
  * Detail: `Process 35752 waits for ShareLock on transaction 872; blocked by process 12856. Process 12856 waits for ShareLock on transaction 873; blocked by process 35752.`
  * Context: `while updating tuple (0,27) in relation "accounts"`.
  * *Explanation*: A circular lock dependency formed. PostgreSQL's background deadlock detector resolved it by terminating process 35752.

---

## Stress test
The stress test parameters and command from `screenshots/integrity.png` and `screenshots/stress_results.png`:
* Command: `pgbench -U postgres -h localhost -n -c 10 -j 4 -t 200 -f <script> quickfund_db`
* Clients (`-c`): 10 concurrent connections
* Threads (`-j`): 4 worker threads
* Transactions per client (`-t`): 200 (Total intended transactions: 2,000)
* Contention Hotspot: Narrow set of 20 accounts (`account_number >= '1000000000' AND account_number < '9000000000' LIMIT 20`)

### Benchmark Comparison Table

| Metric | Ordered Locking (`05_stress_ordered.pgbench`) | Unordered Locking (`06_stress_unordered.pgbench`) | Source / Evidence |
| :--- | :--- | :--- | :--- |
| **Target Function** | `transfer_funds()` | `transfer_funds_unordered()` | Script definition |
| **Lock Acquisition Order** | `LEAST(acc1, acc2)` then `GREATEST` | Sender account first, then Receiver | `01_transfer_function.sql` |
| **Artificial Delay** | None | `pg_sleep(0.01)` | `01_transfer_function.sql` |
| **Failed Transactions (Deadlocks)** | `0` (0.00%) | High / Cascading Deadlock Aborts | `08_exp4_deadlock.png`, `07_integrity_check.sql` |
| **Throughput (TPS)** | Continuous execution without aborts | Stalled / Interrupted by engine aborts | `stress_results.png`, `integrity.png` |
| **System Invariant Preservation** | 100% Invariants Preserved | Aborted transactions rolled back | `own_experiment.png 4.png` |

*Explanation*: Ordered locking constructs a Directed Acyclic Graph (DAG) for all lock requests. Even under intense contention across 20 hot accounts, transactions queue orderly without deadlock cycles.

### Financial Integrity Checks Across Runs
From `07_integrity_check.sql` and `screenshots/own_experiment.png 4.png`:

* **The Three `total_money_in_system` Values**:
  1. Baseline run (before stress tests): `10000000000.00` NGN (source: `07_integrity_check.sql`, `screenshots/own_experiment.png 4.png`)
  2. Post-ordered stress test: `10000000000.00` NGN (source: `07_integrity_check.sql`)
  3. Post-reversal / post-unordered run: `10000000000.00` NGN (source: `screenshots/own_experiment.png 4.png`)

* **Integrity Problem Counts** (source: `screenshots/own_experiment.png 4.png`):
  * `unbalanced_transactions` ($\sum \text{debits} \neq \sum \text{credits}$): `0`
  * `mismatched_accounts` ($\text{balance} \neq \text{net ledger}$): `0`
  * `stuck_pending_transactions`: `0`
  * `stress_transfers` / `stress_ledger_lines`: `0` (before stress) / exactly $2:1$ ratio.

---

## My own experiment
Implemented in `08_own_experiment_reversal.sql`: `reverse_transfer(p_original_id, p_key, p_description)`.

Facts taken from `screenshots/own_experiment.png 1.png`, `screenshots/own_experiment.png 2.png`, `screenshots/own_experiment.png 3.png`, and `screenshots/own_experiment.png 4.png`:

1. **Successful Reversal Run** (`own_experiment.png 1.png`):
   * Original Transfer UUID: `e441be5a-12ba-42eb-bc52-2b9bb075b996`
   * Idempotency Key: `'own-exp-reversal-1'`
   * Returned Reversal UUID: `dcb7336d-7818-4d12-badb-a0bbd888ff06`
   * Retrying same statement returned identical UUID `dcb7336d-7818-4d12-badb-a0bbd888ff06`.
2. **Duplicate Reversal Prevention** (`own_experiment.png 2.png`):
   * Calling `reverse_transfer('e441be5a-12ba-42eb-bc52-2b9bb075b996', 'own-exp-reversal-2')` rejected with:
     `ERROR: NOT_REVERSIBLE: only a SUCCESS transfer can be reversed (status is REVERSED)`
     `CONTEXT: PL/pgSQL function reverse_transfer(uuid,character varying,character varying) line 21 at RAISE`.
   * Current account balances: `2000000955` = `162206.84`, `2000000992` = `162428.45`.
3. **Transaction State & Ledger Balance** (`own_experiment.png 3.png`):
   * Original `e441be5a-12ba-42eb-bc52-2b9bb075b996`: `transaction_type = 'TRANSFER'`, `status = 'REVERSED'`, `amount = 5.00`.
   * Reversal `dcb7336d-7818-4d12-badb-a0bbd888ff06`: `transaction_type = 'REVERSAL'`, `status = 'SUCCESS'`, `amount = 5.00`, `reversal_of = 'e441be5a-12ba-42eb-bc52-2b9bb075b996'`.
   * `SUM(debits - credits)` for both transactions: exactly `0.00`.
4. **Audit Verification** (`own_experiment.png 4.png`):
   * Executed `\i portfolio-3-transactions-concurrency/07_integrity_check.sql`.
   * `total_money_in_system`: `10000000000.00`
   * `unbalanced_transactions`: `0`
   * `mismatched_accounts`: `0`
   * `stuck_pending_transactions`: `0`.

---

## Limitations
* **Row-Level Lock Contention**: While ordered locking eliminates deadlocks, high-frequency access to a single account (e.g. a hot merchant wallet) forces concurrent transactions to serialize in FIFO queues, increasing latency.
* **First-Committer-Wins Aborts in Repeatable Read**: Under `REPEATABLE READ`, concurrent updates to the same row fail with error `40001` rather than waiting. Application layers must implement retry loops with exponential backoff.
* **Single-Node Boundary**: PL/pgSQL row locks (`FOR UPDATE`) operate strictly on a single PostgreSQL instance. Distributed cross-partition transactions require two-phase commit (2PC) or Saga patterns.

---

## Reflection
Testing transactions under concurrency revealed that atomicity and isolation cannot be taken for granted. The difference between `transfer_funds()` and `transfer_funds_unordered()` demonstrates that a few lines of code (enforcing `LEAST` and `GREATEST` lock ordering) make the difference between complete database stability and cascading deadlock crashes. In financial systems, append-only ledgers and mathematical integrity invariants (`07_integrity_check.sql`) are essential safeguards against balance corruption.
