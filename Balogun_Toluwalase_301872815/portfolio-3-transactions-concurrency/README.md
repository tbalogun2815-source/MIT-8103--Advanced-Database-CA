# Portfolio 3: Transactions, Concurrency & ACID Guarantees

## Overview
Portfolio 3 implements and evaluates transaction processing, concurrency control, and ACID guarantees for the QuickFund digital wallet system on PostgreSQL 18.6 (`quickfund_db`). Using a database containing 6,001 accounts, 206,101 transactions, and 412,201 double-entry ledger entries, this portfolio demonstrates:
* Atomic money transfers (`transfer_funds()`) with canonical ordered locking (`LEAST` / `GREATEST` UUID ordering) and idempotency deduplication.
* Real-world transaction controls: `COMMIT`, `ROLLBACK`, automatic failure rollbacks, and nested `SAVEPOINT` recovery.
* Multi-session concurrency phenomena: row-level locking (`FOR UPDATE`), lock wait monitoring via `pg_stat_activity`, statement-level snapshot reads in `READ COMMITTED`, and serialization conflict detection in `REPEATABLE READ`.
* Deadlock reproduction and elimination under high-contention `pgbench` benchmarks.
* A custom, append-only, idempotent transaction reversal function (`reverse_transfer()`) maintaining continuous mathematical conservation of money at 10,000,000,000.00 NGN.

---

## Folder structure
```text
portfolio-3-transactions-concurrency/
├── 01_transfer_function.sql          # Safe atomic transfer and flawed unordered transfer functions
├── 02_demo_setup.sql                 # Disposable test accounts (Demo Alice & Demo Bob, 500 NGN each)
├── 03_commit_rollback_demo.sql       # 5 transaction demos (commit, rollback, error, idempotency, savepoint)
├── 05_stress_ordered.pgbench         # Benchmark script testing ordered locking on 20 hot accounts
├── 06_stress_unordered.pgbench       # Benchmark script exposing deadlocks under unordered locking
├── 07_integrity_check.sql            # 5-point mathematical financial invariant audit suite
├── 08_own_experiment_reversal.sql    # Custom append-only, idempotent reversal function
├── my_notes.txt                      # Study and revision notes in plain English
├── README.md                         # Portfolio documentation and reproduction guide
├── analysis.md                       # Comprehensive facts-based technical analysis report
├── reflection.md                     # Personal engineering reflection report
├── output/
│   ├── .gitkeep
│   └── 03_commit_rollback_output.txt # Execution transcript of commit, rollback, and savepoint demos
└── screenshots/                      # 15 execution evidence screenshots
    ├── 04_exp2_waiting.png
    ├── 06_exp3a_read_committed.png
    ├── 07_exp3b_repeatable_read.png
    ├── 08_exp4_deadlock.png
    ├── commit rollback output .png
    ├── exp2_unblocked.png
    ├── integrity.png
    ├── own_experiment.png 1.png
    ├── own_experiment.png 2.png
    ├── own_experiment.png 3.png
    ├── own_experiment.png 4.png
    ├── PGADMIN graphical counts check.png
    ├── psql counts check.png
    ├── stress_results.png
    └── Test transfer function.png
```

---

## How to reproduce
Execute the following commands in order using PowerShell from the repository root:

```powershell
# 1. Add PostgreSQL bin to PATH (if not already present)
$env:Path += ";C:\Program Files\PostgreSQL\18\bin"

# 2. Deploy transfer functions (safe transfer_funds and demonstration transfer_funds_unordered)
psql -U postgres -h localhost -d quickfund_db -f "portfolio-3-transactions-concurrency/01_transfer_function.sql"

# 3. Initialize / reset demo accounts (Demo Alice 9000000001 and Demo Bob 9000000002 to 500.00 NGN)
psql -U postgres -h localhost -d quickfund_db -f "portfolio-3-transactions-concurrency/02_demo_setup.sql"

# 4. Run Commit, Rollback, Failure, Idempotency, and Savepoint demonstrations
psql -U postgres -h localhost -d quickfund_db -a -f "portfolio-3-transactions-concurrency/03_commit_rollback_demo.sql" > "portfolio-3-transactions-concurrency/output/03_commit_rollback_output.txt" 2>&1

# 5. Run baseline financial integrity check
psql -U postgres -h localhost -d quickfund_db -f "portfolio-3-transactions-concurrency/07_integrity_check.sql"

# 6. Execute high-contention stress test with ordered locking (10 clients, 4 threads, 200 txns each)
pgbench -U postgres -h localhost -n -c 10 -j 4 -t 200 -f "portfolio-3-transactions-concurrency/05_stress_ordered.pgbench" quickfund_db

# 7. Execute high-contention stress test with unordered locking (exposes deadlock cascades)
pgbench -U postgres -h localhost -n -c 10 -j 4 -t 200 -f "portfolio-3-transactions-concurrency/06_stress_unordered.pgbench" quickfund_db

# 8. Deploy and test the custom reversal function (own experiment)
psql -U postgres -h localhost -d quickfund_db -f "portfolio-3-transactions-concurrency/08_own_experiment_reversal.sql"

# 9. Execute post-test financial integrity verification
psql -U postgres -h localhost -d quickfund_db -f "portfolio-3-transactions-concurrency/07_integrity_check.sql"
```

---

## Key findings
All figures are quoted directly from `output/03_commit_rollback_output.txt` and verified in screenshots:
* **Starting Balances**: Account `2000000955` = `162341.84` NGN; Account `2000000992` = `162293.45` NGN.
* **Commit Demo (100.00 NGN)**: After `COMMIT`, balances updated permanently to `162241.84` NGN and `162393.45` NGN (Transaction ID: `76c18356-d32c-4672-a6c0-95779ac19815`).
* **Rollback Demo (100.00 NGN)**: Post-rollback balances reverted to `162241.84` NGN and `162393.45` NGN. Rows for rolled back key = `0` (Transaction ID: `31bf0813-f4d2-4003-bd85-235e360f8ad7`).
* **Insufficient Funds Violation**: Attempted `999999999.00` NGN transfer was aborted by PL/pgSQL exception (`INSUFFICIENT_FUNDS`), leaving balances intact and `rows_for_failed_key = 0`.
* **Idempotency**: Retried call with identical key returned identical UUID `bbdd9ba4-f042-4ac1-9d69-78e5e6b298d3`; exactly `1` transaction row was created, deducting `25.00` NGN only once (balances: `162216.84` and `162418.45`).
* **Savepoint Recovery**: First sub-transfer of `10.00` NGN (`43bd07bb-7b4b-4588-a042-c78cf5b19f4e`) survived when a second failed sub-transfer was rolled back to savepoint (final balances: `162206.84` and `162428.45`).
* **Lock Ordering vs Deadlocks**: In `pgbench` testing across 20 hot accounts, ordered locking produced `0` deadlocks, whereas unordered locking triggered engine aborts (`ERROR: deadlock detected`, process waiting for ShareLock on transaction).
* **Conservation of Money**: Across baseline, stress testing, and custom reversal runs, `total_money_in_system` remained invariant at `10000000000.00` NGN with `0` unbalanced transactions and `0` mismatched accounts.

---

## Evidence

| Screenshot File Name | What it shows |
| :--- | :--- |
| `04_exp2_waiting.png` | |
| `06_exp3a_read_committed.png` | |
| `07_exp3b_repeatable_read.png` | |
| `08_exp4_deadlock.png` | |
| `commit rollback output .png` | |
| `exp2_unblocked.png` | |
| `integrity.png` | |
| `own_experiment.png 1.png` | |
| `own_experiment.png 2.png` | |
| `own_experiment.png 3.png` | |
| `own_experiment.png 4.png` | |
| `PGADMIN graphical counts check.png` | |
| `psql counts check.png` | |
| `stress_results.png` | |
| `Test transfer function.png` | |

---

## Reflection
Working through this portfolio shifted my understanding of database transactions from basic syntax to systems engineering. Implementing ordered locking using `LEAST` and `GREATEST` UUID ordering proved that deadlocks can be mathematically eliminated at the design stage rather than relying on reactive database aborts. Seeing Repeatable Read throw serialization error `40001` highlighted the reality that snapshot isolation requires client-side retry handling. Building `reverse_transfer()` reinforced the fundamental accounting rule of ledger immutability: financial corrections must be append-only mirror transactions rather than destructive updates or deletes.

---

## AI-use declaration
I partially used the Antigravity AI to adapt files, collect numbers from my output files. majority of the experiments were run by me and all screenshots taken by me, and I wrote the explanations myself. I checked results by running every script and reading the output files.
