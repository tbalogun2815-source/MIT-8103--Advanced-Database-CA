# Academic References and Engineering Bibliography

> **Course:** MIT 8103 Advanced Database Systems  
> **Student Name:** Balogun Toluwalase  
> **Student ID:** 301872815  
> **Institution:** Miva Open University  
> **Project:** QuickFund Digital Wallet & Financial Ledger System  
> **Submission Date:** November 2026  

---

## 1. Foundational Database & Relational Theory

1. **Codd, E. F. (1970).** "A Relational Model of Data for Large Shared Data Banks." *Communications of the ACM*, 13(6), 377–387.  
   *Application in Portfolio 1:* Provided the mathematical foundation for relational calculus, first through Boyce-Codd normal forms (1NF–BCNF), candidate key definitions, and primary/foreign key domain integrity constraints across QuickFund's eight core tables (`customers`, `kyc_records`, `accounts`, `beneficiaries`, `cards`, `transactions`, `ledger_entries`, `fraud_flags`).

2. **Date, C. J. (2019).** *Database Design and Relational Theory: Normal Forms and All That Jazz* (2nd ed.). Apress.  
   *Application in Portfolio 1:* Informed the rigorous functional dependency analysis documented in `normalisation.md`, guiding the elimination of insertion, update, and deletion anomalies while theoretically justifying our four deliberate operational denormalisations (e.g., cached `accounts.balance` reconciled against immutable journal lines).

3. **Elmasri, R., & Navathe, S. B. (2015).** *Fundamentals of Database Systems* (7th ed.). Pearson.  
   *Application in Portfolios 1 & 2:* Used for entity-relationship modelling principles, cardinality ratios ($1:1$, $1:N$, recursive self-referencing reversals), weak entity dependencies, and relational algebra cost models used by query optimizers.

---

## 2. Transaction Processing, Concurrency Control, & ACID Guarantees

4. **Gray, J., & Reuter, A. (1993).** *Transaction Processing: Concepts and Techniques*. Morgan Kaufmann Publishers.  
   *Application in Portfolio 3:* The definitive text on ACID properties (Atomicity, Consistency, Isolation, Durability), write-ahead logging (WAL), two-phase locking (2PL), and transaction rollback mechanics implemented in the atomic `transfer_funds()` stored procedure.

5. **Bernstein, P. A., & Newcomer, E. (2009).** *Principles of Transaction Processing* (2nd ed.). Morgan Kaufmann.  
   *Application in Portfolio 3:* Provided the theoretical framework for multi-client transaction scheduling, serialization graphs, and deadlock prevention via canonical resource allocation order (`LEAST(v_from_id, v_to_id)` and `GREATEST(v_from_id, v_to_id)`), eliminating circular wait states during high-concurrency benchmarks.

6. **Berenson, H., Bernstein, P., Gray, J., Melton, J., O'Neil, E., & O'Neil, P. (1995).** "A Critique of ANSI SQL Isolation Levels." *ACM SIGMOD Record*, 24(2), 1–10.  
   *Application in Portfolio 3:* Provided exact mathematical definitions of transaction phenomena (dirty reads, non-repeatable reads, phantom reads, lost updates, and serialization anomalies) evaluated empirically in PostgreSQL 18.6 under `READ COMMITTED` and `REPEATABLE READ`.

---

## 3. Database Internals, Storage Engines, & Query Optimization

7. **PostgreSQL Global Development Group. (2024).** *PostgreSQL 18 Documentation*. PostgreSQL Documentation Project. https://www.postgresql.org/docs/18/  
   *Specific Reference Chapters:*
   - Chapter 14: *Performance Tips & Using EXPLAIN*
   - Chapter 20: *Write-Ahead Logging (WAL) & Reliability*
   - Chapter 27: *High Availability, Load Balancing, and Replication*
   - Chapter 64: *B-Tree Indexes & Storage Internals*
   *Application in Portfolios 2, 3 & 5:* Guided `EXPLAIN (ANALYZE, BUFFERS)` execution plan interpretations, cost formula derivations (`seq_page_cost = 1.0`, `random_page_cost = 4.0`), physical streaming replication slots (`replica1_slot`), standby promotion via `pg_promote()`, and lock monitoring queries on `pg_stat_activity`.

8. **Winand, M. (2012).** *Use the Index, Luke! A Guide to Database Performance for Developers*. 2ndQuadrant.  
   *Application in Portfolio 2:* Directly guided our compound index column ordering (`equality columns first, range/sort columns second`), partial covering indexes with `INCLUDE` clauses (`idx_transactions_transfers_completed_time`), and the elimination of expensive external merge disk sorts (saving 6.5 MB–6.9 MB of disk spills on Q8 and Q11) via leaf-level pre-sorted B-Tree traversals.

9. **Hellerstein, J. M., Stonebraker, M., & Hamilton, J. (2007).** "Architecture of a Database System." *Foundations and Trends in Databases*, 1(2), 141–259.  
   *Application in Portfolios 2 & 3:* Provided architectural insights into relational process models, buffer pool caching dynamics (shared buffer hits vs disk reads), page layout structures (8 kB blocks), and lock manager wait states.

---

## 4. Distributed Systems, Consensus, & Cloud Topologies

10. **Brewer, E. A. (2000).** "Towards Robust Distributed Systems." *ACM Symposium on Principles of Distributed Computing (PODC)*, Portland, OR.  
    *Application in Portfolio 5:* Provided the theoretical basis for the CAP theorem (Consistency, Availability, Partition Tolerance), empirically validated when halting the PostgreSQL read replica under synchronous replication froze write transactions on the primary (`sync_state = sync`).

11. **Gilbert, S., & Lynch, N. (2002).** "Brewer's Conjecture and the Feasibility of Consistent, Available, Partition-Tolerant Web Services." *ACM SIGACT News*, 33(2), 51–59.  
    *Application in Portfolio 5:* Formalized the impossibility proof of simultaneously achieving strict consistency and continuous availability in asynchronous network partitions, underpinning our architectural justification for a 3-node quorum setup.

12. **Abadi, D. J. (2012).** "Consistency Tradeoffs in Modern Distributed Database System Design: CAP is Only Part of the Story." *Computer*, 45(2), 37–42.  
    *Application in Portfolio 5:* Informed the PACELC model analysis (Partition: Availability vs Consistency; Else: Latency vs Consistency) applied to the intercontinental MongoDB Atlas cluster and local PostgreSQL streaming replication lag.

13. **Kleppmann, M. (2017).** *Designing Data-Intensive Applications: The Big Ideas Behind Reliable, Scalable, and Maintainable Systems*. O'Reilly Media.  
    *Application in Portfolios 4 & 5:* The primary engineering reference for replication lag phenomena (read-your-own-writes consistency, stale-read risks on financial balances), log-structured storage engines, hash partitioning schemes, and failover sequence cache jumps.

---

## 5. Polyglot Persistence, NoSQL Architectures, & Document Stores

14. **MongoDB, Inc. (2024).** *MongoDB Manual (Version 8.0)*. MongoDB Documentation. https://www.mongodb.com/docs/manual/  
    *Application in Portfolio 4 & 5:* Guided the implementation of strict JSON Schema Validation (`$jsonSchema`, `validationAction: "error"` with deliberate code 121 rejection), multi-stage aggregation pipelines (`$match`, `$group`, `$sort`, `$limit`, `$lookup`, `$unwind`, `$project`), background TTL index session expiry, and write concern parameters (`w: 1` vs `w: majority`).

15. **Sadalage, P. J., & Fowler, M. (2012).** *NoSQL Distilled: A Brief Guide to the Emerging World of Polyglot Persistence*. Addison-Wesley.  
    *Application in Portfolio 4:* Informed the architectural boundary between PostgreSQL (ACID financial core) and MongoDB (polyglot document store), providing the embedding criteria (bounded 1–4 identity documents in `kyc_profiles`) versus referencing criteria (unbounded 100,000 append-only records in `audit_events`).

16. **Fowler, M. (2017).** "What do you mean by 'Event-Driven'?" *MartinFowler.com*.  
    *Application in Portfolio 4:* Informed the cross-system link design between PostgreSQL customer UUIDs and MongoDB audit event projections, establishing auditability without cross-database transactional coupling.

---

## 6. Financial Accounting, Card Security & Regulatory Frameworks

17. **Central Bank of Nigeria (CBN). (2020).** *Regulatory Framework for the Bank Verification Number (BVN) Operations and Electronic Payments in Nigeria*. Central Bank of Nigeria.  
    *Application across all Portfolios:* Informed QuickFund's multi-tier KYC structure (Tiers 1–3), BVN/NIN verification requirements, daily transaction limits, and electronic payment audit mandates.

18. **Central Bank of Nigeria (CBN). (2011).** *Standards on Nigeria Uniform Bank Account Number (NUBAN) Scheme*. Central Bank of Nigeria Banking Operations Department.  
    *Application in Portfolio 1:* Governed the 10-digit unique account numbering format enforced at schema level via `CHECK (account_number ~ '^[0-9]{10}$')`.

19. **PCI Security Standards Council. (2022).** *Payment Card Industry Data Security Standard (PCI DSS) v4.0*. PCI SSC.  
    *Application in Portfolio 1:* Governed the Primary Account Number (PAN) masking requirements implemented in the `cards` table, enforcing storage of only the last 4 digits via `CHECK (last_four ~ '^[0-9]{4}$')` alongside token hashes.

20. **International Accounting Standards Board (IASB). (2018).** *Conceptual Framework for Financial Reporting*. IFRS Foundation.  
    *Application in Portfolios 1 & 3:* Guided the design of the immutable double-entry ledger, ensuring that every financial movement records balanced debits and credits ($\sum \text{Debits} = \sum \text{Credits}$) with zero floating-point rounding errors and 0.00 kobo balance drift.
