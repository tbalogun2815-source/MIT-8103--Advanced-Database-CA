# Relational Normalisation & Strategic Denormalisation Report

**Course**: MIT-8103: Advanced Database Systems  
**Project**: Continuous Assessment — Portfolio 1: Database Design  
**Author**: [@tbalogun2815-source](https://github.com/tbalogun2815-source)  
**System**: QuickFund Digital Wallet & Ledger Architecture  

---

## 1. Executive Summary

Relational database theory establishes **Third Normal Form (3NF)** and **Boyce-Codd Normal Form (BCNF)** as gold standards for eliminating data redundancy, preventing insertion/update/deletion anomalies, and enforcing functional dependency integrity. 

However, in high-throughput enterprise financial architectures (fintech, core banking, and digital wallets), strict adherence to 3NF can impose catastrophic performance bottlenecks on real-time Online Transaction Processing (OLTP) workloads. High-frequency operations—such as sub-second balance checks, payment gateway idempotency lookups, and point-in-time audit reconciliations—cannot afford expensive recursive joins and full-history table aggregations.

This document presents a rigorous normalisation analysis of the QuickFund database schema, detailing where the schema strictly satisfies 3NF/BCNF, and providing a formal justification for four **deliberate, strategic violations of 3NF**:
1. `accounts.balance` (Derived aggregate attribute)
2. `ledger_entries.balance_after` (Point-in-time running balance snapshot)
3. `transactions.amount` (Redundant multi-legged transactional total)
4. `beneficiaries.account_name` (Transitive external dependency snapshot)

---

## 2. Normalisation Foundations (1NF through BCNF)

To evaluate the QuickFund schema, we evaluate each relation against the classical relational criteria:

* **First Normal Form (1NF)**:
  - All attributes contain atomic, indivisible values.
  - No repeating groups or multivalued arrays are stored in a single column.
  - Every table has a clearly defined primary key.
* **Second Normal Form (2NF)**:
  - Relation is in 1NF.
  - No partial functional dependencies exist: every non-prime attribute is fully functionally dependent on the *entire* primary key (specifically applicable to composite primary keys).
* **Third Normal Form (3NF)**:
  - Relation is in 2NF.
  - No transitive functional dependencies exist: non-prime attributes must depend *only* on candidate keys ($X \to Y$ requires $X$ to be a superkey or $Y$ to be a prime attribute).
* **Boyce-Codd Normal Form (BCNF)**:
  - A stricter version of 3NF where for *every* non-trivial functional dependency $X \to Y$, $X$ must be a superkey.

---

## 3. Baseline Schema Normalisation Review

The majority of QuickFund's entities strictly adhere to **3NF / BCNF**:

| Table | Primary Key | Functional Dependencies | Normal Form |
| :--- | :--- | :--- | :--- |
| **`customers`** | `customer_id` | `customer_id` $\to$ `first_name`, `last_name`, `customer_type`, `is_active`, `created_at`<br>`email` $\to$ `customer_id` (Candidate Key)<br>`phone` $\to$ `customer_id` (Candidate Key) | **BCNF** |
| **`kyc_records`** | `kyc_id` | `kyc_id` $\to$ `customer_id`, `tier_level`, `id_type`, `id_number`, `status`, `verified_at` | **BCNF** |
| **`cards`** | `card_id` | `card_id` $\to$ `account_id`, `card_token`, `last_four`, `card_type`, `card_brand`, `expiry_month`, `expiry_year`, `status` | **BCNF** |
| **`fraud_flags`** | `flag_id` | `flag_id` $\to$ `transaction_id`, `risk_score`, `risk_level`, `reason`, `status`, `flagged_at` | **BCNF** |

In these tables, all non-key attributes depend solely and directly on the primary key, with zero transitive dependencies or derived values.

---

## 4. Deliberate 3NF Violations (Strategic Denormalisation)

In real-world financial engineering, selective denormalisation is intentionally applied to balance relational purity against operational latency, system throughput, and audit immutability.

```
                          QuickFund Relational Core
                                     │
         ┌───────────────────────────┼───────────────────────────┐
         ▼                           ▼                           ▼
  accounts.balance        ledger_entries.balance_after   transactions.amount
 (Derived Summation)      (Point-in-Time Snapshot)     (Redundant Ledger Total)
  • Eliminates O(N) scan   • Instant statement lookup   • Fast gateway checks
  • Row-level lock target  • Zero-sum discrepancy audit • Split-payment parent
```

---

### 4.1. `accounts.balance`

#### The 3NF Violation: Derived Attribute
In pure relational theory, an account balance is not an independent state; it is mathematically derived from the sum of all historical double-entry ledger postings for that account:

$$\text{Balance} = \sum (\text{CREDIT Amounts}) - \sum (\text{DEBIT Amounts})$$

By storing `balance` as a persisted column in the `accounts` table, the schema introduces a **transitive dependency**:
$$\text{ledger\_entries}(\text{account\_id}, \text{entry\_direction}, \text{amount}) \to \text{accounts.balance}$$
This formally violates **3NF**, creating potential update anomalies if the ledger and account balance drift out of sync.

#### Why We Deliberately Break 3NF
1. **$O(1)$ vs $O(N)$ Read Latency**: Digital wallets process millions of authorization requests (card swipes, ATM withdrawals, airtime top-ups). Evaluating balance sufficiency by executing `SELECT SUM(...) FROM ledger_entries WHERE account_id = ?` requires scanning hundreds or thousands of rows per user, resulting in unmanageable $O(N)$ I/O overhead. Persisting `balance` allows instant $O(1)$ indexed reads.
2. **Pessimistic Concurrency Control**: In high-concurrency environments, double-spending is prevented by locking the specific account row using `SELECT balance FROM accounts WHERE account_id = ? FOR UPDATE`. Locking a single row in `accounts` is drastically cheaper and less disruptive than locking entire ranges of child ledger entries.
3. **Database Check Constraint**: The column allows the database engine to enforce non-negative balances at the hardware level via `CONSTRAINT chk_account_balance_positive CHECK (balance >= 0.00)`.

#### Mitigation Mechanism
- Balance mutations must occur **strictly within atomic database transactions** (`BEGIN ... COMMIT`) alongside the corresponding `ledger_entries` insertions.
- Automated nightly reconciliation jobs execute background verification to prove:
  $$\text{accounts.balance} - \left( \sum \text{Credits} - \sum \text{Debits} \right) = 0.00$$

---

### 4.2. `ledger_entries.balance_after`

#### The 3NF Violation: Redundant Running Total
`balance_after` represents the exact balance of an account immediately following the execution of a specific debit or credit ledger entry. Because `balance_after` is a running total calculated from the previous entry's `balance_after` $\pm$ `amount`, it represents redundant state derived across historical rows. Storing it violates **3NF**.

#### Why We Deliberately Break 3NF
1. **Point-in-Time Statement Generation**: Financial statements require displaying the resulting balance after every line item. Without `balance_after`, generating an account statement for 50 transactions requires computing window functions over the user's entire account lifetime. With `balance_after`, statements can be rendered through simple, paginated slice queries.
2. **Immutability & Tamper-Evident Auditing**: In forensic accounting, ledger entries must be append-only and cryptographically auditable. If an unauthorized actor directly manipulates a past ledger row or injects a fraudulent entry, the continuous sequence of `balance_after` values breaks, instantly exposing the exact point of tampering.
3. **Sub-ledger Discrepancy Detection**: Regulators and Central Bank auditors require continuous proof of financial consistency. Comparing the latest `ledger_entries.balance_after` with `accounts.balance` provides an instantaneous $O(1)$ health check.

#### Mitigation Mechanism
- Ledger entries are strictly append-only; update and delete privileges are revoked via PostgreSQL permissions (`ON DELETE RESTRICT` and role-based access control).
- Application service layers or database stored procedures guarantee that:
  $$\text{balance\_after}_{\text{new}} = \text{balance\_after}_{\text{previous}} + \text{signed\_amount}$$

---

### 4.3. `transactions.amount`

#### The 3NF Violation: Redundant Aggregate Across Related Entities
In double-entry bookkeeping, a transaction is an event that generates balanced ledger records:
$$\text{Total Debits} = \text{Total Credits} = \text{Transaction Amount}$$
Storing `amount` on `transactions` when the exact same numerical value is already recorded in the corresponding `ledger_entries` child rows constitutes **cross-table data duplication**, violating **3NF**.

#### Why We Deliberately Break 3NF
1. **Decoupled Transaction Ingestion & Idempotency**: When a client or payment gateway posts a transaction request, the system immediately checks the `idempotency_key` and creates a `PENDING` transaction record before ledger posting occurs. Persisting the intended transaction amount upfront ensures the requested value is locked before ledger orchestration begins.
2. **Multi-Legged & Split-Payment Audits**: While simple peer-to-peer transfers involve two equal entries, complex fintech transactions involve multiple splits (e.g., Transfer Amount: ₦10,000; Processing Fee: ₦100; VAT: ₦7.50). `transactions.amount` preserves the top-level contract value agreed to by the customer, while the ledger breaks down the multi-party distribution.
3. **High-Level Reporting & Indexing**: Querying transaction volumes, filtering transaction feeds by size, and evaluating AML (Anti-Money Laundering) thresholds are performed frequently on `transactions(amount, created_at)` without executing expensive joins across millions of ledger records.

#### Mitigation Mechanism
- Business rules enforce balanced postings:
  $$\sum \text{ledger\_entries.amount (DEBITS)} = \sum \text{ledger\_entries.amount (CREDITS)} = \text{transactions.amount}$$
- Stored procedures and application units of work reject any transaction where the sum of ledger legs does not reconcile with the parent transaction amount.

---

### 4.4. `beneficiaries.account_name`

#### The 3NF Violation: Transitive Dependency on Destination Account
In a normalized relational schema, an account name is an attribute of the account entity ($account\_number \to account\_name$). Storing `account_name` inside `beneficiaries` introduces a **transitive dependency**:
$$\text{beneficiary\_id} \to \text{beneficiary\_account\_number} \to \text{account\_name}$$
Under strict 3NF rules, `account_name` should be fetched on the fly via a join on `accounts.account_number`.

#### Why We Deliberately Break 3NF
1. **External Inter-Bank Architecture (NIBSS / NIP)**: QuickFund is an open fintech ecosystem where customers transfer money not only to other QuickFund wallets, but to external commercial banks across Nigeria (e.g., Access Bank, GTBank, Zenith Bank). External accounts **do not exist** in QuickFund's internal `accounts` table. The account name is resolved once via an external NIBSS name inquiry API and must be saved locally.
2. **Immutable Contact Snapshot**: Even for internal transfers, a customer saves a beneficiary under the legal name verified at that specific moment. If the recipient later changes their name or updates their account status, the sender's saved address book should not silently mutate without the sender's awareness.
3. **Elimination of Cross-System API Calls**: Fetching a customer's transfer screen displays their saved beneficiaries. Storing `account_name` denormalized avoids making 10–20 third-party bank network API calls every time a user opens their transfer dashboard.

#### Mitigation Mechanism
- Field length constraints and sanitization prevent malformed name strings.
- Beneficiary account numbers are bound by `chk_beneficiary_acc_num` (10-digit NUBAN regex), and composite uniqueness is enforced on `(customer_id, beneficiary_account_number, bank_name)`.

---

## 5. Strategic Denormalisation Matrix

The table below summarizes the four deliberate trade-offs, contrasting pure academic normalisation with enterprise production requirements:

| Column | Theoretical Status | Normal Form Broken | Root Cause of Violation | Engineering Rationale | Architectural Safeguard |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`accounts.balance`** | Derived value | **3NF** | Derivable from $\sum \text{Ledger Entries}$ | $O(1)$ read latency, row-level locking, non-negative CHECK | ACID transactions, automated balance-ledger reconciliation |
| **`ledger_entries.balance_after`** | Redundant snapshot | **3NF** | Cumulative running balance over historical rows | Point-in-time statements, tamper-evident audit trail | Append-only ledger; updates and deletes revoked |
| **`transactions.amount`** | Redundant duplicate | **3NF** | Duplicated across child ledger debit/credit rows | Pre-ledger idempotency locking, split-fee transaction parent | Application validation enforcing $\sum \text{Legs} = \text{Amount}$ |
| **`beneficiaries.account_name`** | Transitive attribute | **3NF** | Transitive: $AccNo \to AccName$ | External inter-bank persistence, eliminates 3rd-party API calls | NUBAN regex check, recipient composite uniqueness |

---

## 6. Conclusion

In the QuickFund system, normalisation is treated as a rigorous design foundation rather than a dogmatic constraint. 

By structuring the entity core (`customers`, `kyc_records`, `cards`, `fraud_flags`) in **BCNF/3NF**, the schema guarantees relational integrity and prevents anomalies. Concurrently, by selectively and intentionally denormalising **`accounts.balance`**, **`ledger_entries.balance_after`**, **`transactions.amount`**, and **`beneficiaries.account_name`**, the platform delivers the sub-millisecond latency, immutable auditability, and inter-bank interoperability demanded by modern enterprise fintech standards.
