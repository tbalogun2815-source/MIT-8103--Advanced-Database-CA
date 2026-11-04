# Portfolio 3: Personal Engineering Reflection

**Course**: MIT-8103: Advanced Database Systems  
**Module**: Continuous Assessment — Portfolio 3: Transactions, Concurrency & ACID Guarantees  
**Project**: QuickFund Digital Wallet & Financial Ledger System  
**Author**: [@tbalogun2815-source](https://github.com/tbalogun2815-source)  
**Date**: November 2026  

---

## 1. Introduction & Context

When I began this continuous assessment module, I viewed database transactions primarily as an administrative wrapper: you type `BEGIN`, you execute some `UPDATE` statements, and you type `COMMIT`. If an error occurs, you run `ROLLBACK`. On paper, the ACID acronym (Atomicity, Consistency, Isolation, Durability) felt like a straightforward textbook checklist that relational database engines magically handled under the hood.

Working through **Portfolio 3** on the **QuickFund** financial platform completely dismantled that simplistic assumption. Once high concurrency enters the picture—multiple users transferring funds between overlapping accounts at the exact same millisecond—the database engine ceases to be a passive storage layer and becomes a complex distributed synchronization engine. 

This reflection captures my personal technical journey through designing atomic financial functions, diagnosing concurrency anomalies, engineering deadlock prevention strategies, and designing a production-grade transaction reversal mechanism.

---

## 2. Key Discoveries & Technical "Aha!" Moments

### 2.1 The Elegance and Necessity of Canonical Ordered Locking

The most profound realization of this portfolio occurred during Experiment 4 and the stress-testing benchmark. When testing naive, unordered transfers (`transfer_funds_unordered()`), I observed how trivially easy it is to bring a database to its knees. If Alice transfers 10 NGN to Bob at the exact instant Bob transfers 10 NGN to Alice:
1. Session 1 locks Alice and waits for Bob.
2. Session 2 locks Bob and waits for Alice.

Both sessions freeze. Although PostgreSQL's deadlock detector faithfully detected the circular wait graph and terminated one of the sessions after one second (`ERROR: deadlock detected`), relying on database engine aborts in production is unacceptable—it degrades throughput, frustrates end users, and floods application logs with runtime errors.

The solution—canonical ordered locking—was an intellectual turning point for me:

```sql
v_first_id  := LEAST(v_from_id, v_to_id);
v_second_id := GREATEST(v_from_id, v_to_id);

PERFORM 1 FROM accounts WHERE account_id = v_first_id  FOR UPDATE;
PERFORM 1 FROM accounts WHERE account_id = v_second_id FOR UPDATE;
```

By enforcing a simple mathematical rule that *every* transaction must lock accounts in alphabetical or numerical UUID sequence, the circular wait condition (Coffman's 4th condition) is dismantled. Seeing `pgbench` hammer 20 hot accounts across 10 concurrent threads with **zero deadlocks** under ordered locking was one of the most satisfying moments of the entire course.

### 2.2 The Subtlety of Isolation Levels: Read Committed vs Repeatable Read

Before this assessment, I assumed that setting `REPEATABLE READ` was always strictly superior to `READ COMMITTED`. Experiment 3 proved how nuanced that choice actually is:

1. In **Read Committed**, each query gets a new snapshot. When Session 2 updated and committed an account balance, Session 1's subsequent `SELECT` within the same transaction immediately saw the new balance. This demonstrated a classic non-repeatable read. However, `READ COMMITTED` rarely aborts transactions outright; it simply blocks and proceeds once locks release.
2. In **Repeatable Read**, Session 1 maintained an immutable snapshot of the balance as it existed when the transaction started. But when Session 1 subsequently attempted to update that row after Session 2 had committed a change, PostgreSQL immediately threw:
   ```text
   ERROR: could not serialize access due to concurrent update
   ```

Experiencing this firsthand clarified PostgreSQL's **First-Committer-Wins** rule. Snapshot isolation prevents lost updates not by waiting, but by failing the second committer. This taught me a vital engineering lesson: *isolation levels are not free configuration toggles*. If an application adopts `REPEATABLE READ` or `SERIALIZABLE`, the engineering team must build an application-layer retry framework with exponential backoff to handle SQLSTATE `40001` serialization failures.

### 2.3 The Hidden Danger of `now()` vs `clock_timestamp()`

Another subtle but critical insight involved timestamp generation for financial statements. In standard PostgreSQL, `now()` (or `CURRENT_TIMESTAMP`) returns the timestamp of the *transaction start time*. 

In an OLTP ledger under heavy concurrency, Transaction A might begin at 12:00:00, experience a brief lock wait, and commit at 12:00:04. Meanwhile, Transaction B might start at 12:00:02 and commit immediately at 12:00:03. If both use `now()`, the account statement will display Transaction A's ledger entries as having happened *before* Transaction B, even though Transaction B committed first.

Switching to `clock_timestamp()` ensured that ledger entries capture the physical wall-clock time at the precise moment the row is written, preserving monotonic chronological ordering for audit feeds.

---

## 3. Practical Challenges & How I Solved Them

### 3.1 Isolating Test Data from the Core Ledger

One challenge I faced was how to run interactive, intentionally failing experiments (like deadlocks and forced rollbacks) without corrupting or cluttering the 400,000+ ledger rows seeded in Portfolio 1. 

To solve this, I wrote [`02_demo_setup.sql`](file:///c:/Users/DELL/Downloads/MIT-8103--Advanced-Database-CA/MIT-8103%20Advanced%20CA%20project/portfolio-3-transactions-concurrency/02_demo_setup.sql), creating two dedicated test accounts: Demo Alice (`9000000001`) and Demo Bob (`9000000002`). I deliberately excluded accounts starting with `9000...` from the double-entry audit checks in [`07_integrity_check.sql`](file:///c:/Users/DELL/Downloads/MIT-8103--Advanced-Database-CA/MIT-8103%20Advanced%20CA%20project/portfolio-3-transactions-concurrency/07_integrity_check.sql). This gave me an isolated sandbox where I could repeatedly reset balances to 500.00 NGN and run destructive concurrency tests without affecting system-wide audit invariants.

### 3.2 Diagnosing In-Flight Locks

When running concurrent sessions in separate psql terminals, Session 2 would simply hang with a blinking cursor. Initially, it was hard to prove whether Session 2 was deadlocked, sleeping, or waiting on an exclusive lock. 

Learning to query `pg_stat_activity` with filters on `wait_event_type = 'Lock'` and `wait_event = 'transactionid'` was empowering. It allowed me to look directly into PostgreSQL's internal lock manager and confirm the exact process IDs (PIDs) involved, transforming an invisible freeze into an observable, measurable event.

---

## 4. Reflections on the "Own Experiment" — Reversal Engineering

For my independent experiment, I chose to tackle **Financial Reversals** ([`08_own_experiment_reversal.sql`](file:///c:/Users/DELL/Downloads/MIT-8103--Advanced-Database-CA/MIT-8103%20Advanced%20CA%20project/portfolio-3-transactions-concurrency/08_own_experiment_reversal.sql)). 

In junior software engineering discussions, you often see developers ask: *"How do I undo a payment? Can I just delete the row or subtract the money back?"* 

Building `reverse_transfer()` reinforced the fundamental accounting rule of **immutability**:
* Financial ledgers are strictly append-only. 
* To undo a transfer, you do not erase history; you append a new `REVERSAL` transaction with mirror debit and credit lines.

Designing this function forced me to consider several real-world edge cases:
1. **Double-Reversal Attacks**: What happens if an operator clicks "Reverse" twice? I locked the original transaction row with `FOR UPDATE` and validated that its status was strictly `'SUCCESS'`. Once reversed, its status transitioned to `'REVERSED'`, making subsequent reversal attempts fail immediately with `NOT_REVERSIBLE`.
2. **Receiver Solvency**: What if the recipient of the original payment has already withdrawn or spent the money? A naive reversal would cause an unauthorized overdraft. My function inspects the receiver's current balance *after* acquiring row locks, aborting with `INSUFFICIENT_FUNDS` if the receiver cannot cover the reversal.
3. **Audit Trail Linkage**: By storing `reversal_of` foreign keys, every reversal explicitly points back to its originating transfer, providing an unbroken audit trail for compliance officers.

Running the full integrity check after reversing a live transaction and seeing `total_money_in_system = 10,000,000,000.00` with zero unbalanced entries proved that the reversal architecture was sound.

---

## 5. What I Would Do Differently / Next Steps

Reflecting on the finished portfolio, there are two enhancements I would explore in future iterations:
1. **Advisory Locks for Application-Level Queuing**: While row-level `FOR UPDATE` locks work well, extreme contention on high-frequency merchant accounts (e.g., an airline payment gateway) can saturate PostgreSQL's lock table. Exploring PostgreSQL advisory locks (`pg_advisory_xact_lock`) or application-level message queues (e.g. RabbitMQ / Kafka) to serialize transfers before they reach the database could reduce lock wait times.
2. **Automated Application Retries for Snapshot Failures**: In the application layer (e.g. Python or Node.js), I would implement a robust retry decorator that intercepts PostgreSQL error code `40001` (serialization failure) and retries the transaction up to 3 times with jittered exponential backoff.

---

## 6. Conclusion

Portfolio 3 has been the most technically challenging and illuminating segment of this course so far. It moved me beyond writing declarative SQL queries and challenged me to think like a systems architect. 

I now deeply understand that maintaining data integrity is not an accidental property of relational databases—it is the result of deliberate architectural choices: canonical lock hierarchies, atomic transaction boundaries, strict idempotency keys, and immutable double-entry ledgers. These principles form the bedrock of trustworthy financial software, and the skills I have developed here will directly inform my future work in distributed systems and backend engineering.

