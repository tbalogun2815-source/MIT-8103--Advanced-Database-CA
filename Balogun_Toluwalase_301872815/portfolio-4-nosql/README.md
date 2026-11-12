# Portfolio 4: NoSQL with MongoDB (QuickFund)

## 1. What I stored in MongoDB, and why

| Data | Lives in|
|---|---|
| Wallets, balances, transfers, ledger | PostgreSQL | Requires strict ACID transactions, double-entry bookkeeping ($\sum \text{debits} = \sum \text{credits}$), foreign keys, check constraints (`balance >= 0`), and exact `NUMERIC(15,2)` math without floating-point rounding errors. |
| KYC profiles (5,000) | MongoDB `kyc_profiles` | Polymorphic, semi-structured documents. Different verification documents (BVN, NIN, Passport, Driver's License) have completely different fields (e.g. passport has expiry and issuing country; BVN has a verification agency). Storing this in SQL would produce wide, sparse tables with mostly `NULL` columns. |
| Audit events (100,000) | MongoDB `audit_events` | High-velocity, append-only event stream. Different event types carry different nested payload structures in `details` (e.g., fraud flags have rules and risk scores; login failures have IP addresses and reasons). Flexible schema accommodates new event types without DDL schema migrations. |
| Login sessions | MongoDB `login_sessions` | Temporary authentication tokens that expire quickly. Ideal for MongoDB's built-in Time-To-Live (TTL) index, which purges stale sessions automatically in the background without needing scheduled database cleanup cron jobs. |

The core financial ledger must stay in PostgreSQL because moving money requires atomic consistency across multiple tables. When a transfer executes, the database must atomically debit one account, credit another, insert two double-entry ledger lines, and enforce domain check constraints (`balance >= 0.00`). PostgreSQL guarantees serializable transaction isolation, strict foreign key referential integrity, and exact decimal arithmetic. MongoDB's distributed document design favors high ingestion speed and flexible schemas, but it lacks cross-collection declarative constraints and relational ledger invariants essential for financial solvency.

---

## 2. The link between the two systems
`customer_id` in MongoDB is the UUID text of `customers.customer_id` in PostgreSQL.

Because PostgreSQL and MongoDB are independent database engines running on separate servers, there is no cross-database foreign key constraint between them. If an administrator deletes a customer record in PostgreSQL, MongoDB has no built-in mechanism to prevent or cascade that deletion, leaving orphaned KYC documents, active sessions, and historical audit logs pointing to an ID that no longer exists in PostgreSQL. To keep the systems consistent, the application layer (or an event-driven message bus like Kafka or RabbitMQ) must orchestrate cross-system lifecycle events—such as using soft deletes (`status = 'DEACTIVATED'`) in PostgreSQL and coordinating cleanup routines in MongoDB.

---

## 3. Data model

### Sample KYC Document (`kyc_profiles`)
```json
{
  "_id": ObjectId("6aeeb6355d1b11df6d5ffc7a"),
  "customer_id": "00038243-21c7-41f4-bc96-8a9404e841c9",
  "tier": 1,
  "status": "VERIFIED",
  "documents": [
    {
      "type": "BVN",
      "number": "22212345678",
      "verified_with": "NIBSS"
    }
  ],
  "created_at": ISODate("2025-03-09T05:25:09.875Z")
}
```

### Sample Audit Event (`audit_events`)
```json
{
  "_id": ObjectId("6aeeb6385d1b11df6d601002"),
  "customer_id": "f5154011-f3d8-472b-b612-60cf67f3fca0",
  "event_type": "TRANSFER_INITIATED",
  "ts": ISODate("2026-10-05T19:19:17.753Z"),
  "details": {
    "reference": "ref-2149282946",
    "amount": Decimal128("3371.05"),
    "channel": "USSD"
  }
}
```

Identity documents are embedded directly inside `kyc_profiles` because every customer has a small, strictly bounded number of identity credentials (typically 1 to 4 documents: BVN, NIN, Passport, or Utility Bill). Embedding them allows the customer profile and all verification documents to be fetched in a single network read. Conversely, audit events grow unbounded over the lifetime of a customer (thousands of logins, transfers, pin changes, and fraud checks). If audit events were embedded inside the customer profile, the document would grow indefinitely, triggering frequent on-disk reallocation, degrading query performance, and eventually crashing into MongoDB's hard 16 MB BSON document size limit.

---

## 4. Schema validation
MongoDB supports JSON Schema validation to enforce structural constraints while retaining field flexibility:
* **Required Fields**: `kyc_profiles` requires `customer_id`, `tier`, `status`, `documents`, and `created_at`. `audit_events` requires `customer_id`, `event_type`, `ts`, and `details`.
* **UUID Pattern**: `customer_id` is validated against the regex `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$` to guarantee exact syntactic parity with PostgreSQL's 36-character canonical UUID format.
* **Enumerated Values**: `status` is restricted to `['PENDING', 'VERIFIED', 'REJECTED']` and `tier` to numbers `1` through `3`, preventing invalid data entry (e.g. status `'MAYBE'`).
* **Nested Array Validation**: `documents` requires at least one item (`minItems: 1`), where each embedded object must have `type` and `number`, with `type` restricted to `['BVN', 'NIN', 'PASSPORT', 'DRIVERS_LICENCE', 'UTILITY_BILL']`.

**Validation Proof** (from `01_schema_validation.png`):
An invalid document (`{ customer_id: 'not-a-uuid', status: 'MAYBE' }`) was rejected by the engine:
```text
PASS: invalid KYC document rejected -> DocumentValidationFailure (code 121)
```

---

## 5. CRUD and aggregation
Seed result: 5,000 profiles (tier 1: 2,741, tier 2: 1,660, tier 3: 599) and 100,000 events.

### Selected Aggregation Pipeline: Top 5 Customers by Failed Logins with KYC Tier ($lookup JOIN)
```javascript
nosql.audit_events.aggregate([
  { $match: { event_type: 'LOGIN_FAILED' } },
  { $group: { _id: '$customer_id', failed_logins: { $sum: 1 } } },
  { $sort: { failed_logins: -1, _id: 1 } },
  { $limit: 5 },
  { $lookup: { from: 'kyc_profiles', localField: '_id', foreignField: 'customer_id', as: 'kyc' } },
  { $unwind: '$kyc' },
  { $project: { _id: 0, customer_id: '$_id', failed_logins: 1, tier: '$kyc.tier', status: '$kyc.status' } }
])
```

### Stage-by-Stage Explanation
1. **`$match`**: Scans the 100,000 events and keeps only those where `event_type` is `'LOGIN_FAILED'`, filtering out unrelated events early.
2. **`$group`**: Groups the filtered events by `customer_id` and counts the occurrences using `{ $sum: 1 }` into `failed_logins`.
3. **`$sort`**: Sorts the grouped customers descending by `failed_logins` so that accounts with the highest failed attempts appear at the top.
4. **`$limit`**: Restricts the pipeline to the top 5 records before joining, saving memory and processing overhead.
5. **`$lookup`**: Performs a left outer join to the `kyc_profiles` collection, matching the audit event's `_id` (`customer_id`) against `kyc_profiles.customer_id`.
6. **`$unwind`**: Flattens the resulting 1-element `kyc` array into a flat subdocument.
7. **`$project`**: Shapes the output document by suppressing `_id` and exposing `customer_id`, `failed_logins`, `tier`, and `status`.

### SQL Equivalent Query
```sql
SELECT a.customer_id, COUNT(*) AS failed_logins, k.tier, k.status
FROM audit_events a
JOIN kyc_profiles k ON k.customer_id = a.customer_id
WHERE a.event_type = 'LOGIN_FAILED'
GROUP BY a.customer_id, k.tier, k.status
ORDER BY failed_logins DESC, a.customer_id ASC
LIMIT 5;
```

---

## 6. Indexing and performance

| Query | Before: stages, docs examined, ms | After: stages, docs examined, ms |
|---|---|---|
| Q1 latest 20 events for one customer | SORT > COLLSCAN, 100,000 docs examined, 63 ms | LIMIT > FETCH > IXSCAN, 20 docs examined, 1 ms |
| Q2 FRAUD_FLAG events, last 7 days | COLLSCAN, 100,000 docs examined, 60 ms | FETCH > IXSCAN, 373 docs examined, 2 ms |
| Q3 KYC profile for one customer | COLLSCAN, 5,000 docs examined, 6 ms | EXPRESS_IXSCAN, 1 doc examined, 1 ms |

### Technical Analysis
* **`COLLSCAN` vs `IXSCAN`**: `COLLSCAN` (collection scan) inspects every document in storage sequentially (100,000 records). `IXSCAN` (index scan) navigates an ordered B-Tree structure directly to the matching leaf entries, reading only the exact keys needed.
* **Compound Index Serving Filter and Sort**: The index `idx_audit_customer_ts` is defined as `{ customer_id: 1, ts: -1 }`. Because keys are partitioned by `customer_id` and pre-sorted in reverse chronological order on disk, MongoDB reads the top 20 documents directly from the index, eliminating the blocking in-memory `SORT` stage entirely.
* **TTL Index Appropriateness**: `login_sessions` uses `{ created_at: 1 }` with `expireAfterSeconds: 3600`. This is ideal for sessions because auth tokens become invalid after one hour and need automatic purging. Applying a TTL index to `audit_events` would be unacceptable because audit logs are legally mandated financial records that must be permanently preserved.
* **Index Maintenance Cost**: Every index requires storage space in RAM and disk, and imposes a write penalty—every insert, update, and delete must update the corresponding B-Tree nodes.
* **Index Sizes** (source: `output/04_indexes_explain.txt` & `output/05_own_partial_index.txt`):
  * `audit_events`: Data = **18.0 MB**, Total Indexes = **5.7 MB** (`_id_`: 3,308 KB, `idx_audit_customer_ts`: 1,400 KB, `idx_audit_type_ts`: 1,112 KB, `idx_audit_fraud_partial`: 72 KB).
  * `kyc_profiles`: Data = **1.4 MB**, Total Indexes = **0.4 MB**.

---

## 7. SQL versus MongoDB for QuickFund (150 to 250 words)
QuickFund uses a hybrid polyglot architecture because neither database engine is universally optimal for every workload. PostgreSQL provides ACID guarantees, multi-row transaction isolation, foreign key enforcement, and exact numeric arithmetic (`NUMERIC(15,2)`). This makes PostgreSQL non-negotiable for the financial core—transferring money, updating wallet balances, and maintaining an immutable double-entry ledger where debits must strictly equal credits. Moving the ledger to MongoDB would introduce severe risks: MongoDB is historically designed around a BASE consistency model (Basically Available, Soft state, Eventual consistency), lacks cross-collection referential constraints, and performs floating-point representations that risk precision drift. 

Conversely, MongoDB excels where relational databases struggle: handling semi-structured, polymorphic data and high-velocity append-only streams. KYC verification documents feature varied fields (passports require expiry dates, BVNs require verification authorities) that fit cleanly into nested BSON arrays without schema migrations. Audit event streams (100,000+ entries) ingest rapidly without locking relational tables. By keeping balances in PostgreSQL and delegating polymorphic documents and audit logs to MongoDB, QuickFund achieves high-throughput scalability while preserving financial integrity.

---

## 8. My own work
* **What I built**: In `05_own_partial_index.js`, I created a partial index on `audit_events` specifically for fraud events:
  ```javascript
  nosql.audit_events.createIndex(
    { ts: -1 },
    { name: 'idx_audit_fraud_partial', partialFilterExpression: { event_type: 'FRAUD_FLAG' } }
  );
  ```
* **My prediction**: Because `FRAUD_FLAG` represents only ~5% of all audit events (5,024 out of 100,000), indexing only fraud documents will dramatically reduce disk footprint while matching or exceeding the speed of the full index.
* **What happened**: 
  * **Storage**: The full index `idx_audit_type_ts` consumes **1,112 KB**, whereas the partial index `idx_audit_fraud_partial` consumes only **72 KB**—a **93.5% reduction in index size**.
  * **Execution Speed**: The fraud query using the partial index dropped execution latency from **14 ms** (full index) down to **1 ms** (partial index), examining identical documents (367 examined, 367 returned).
  * **Safety**: Queries for other events (e.g. `LOGIN_FAILED`) cannot use the partial index and safely fall back to the standard index.

---

## 9. How to reproduce
Run from the project folder, with `MONGODB_URI` set in the terminal (never in a file):
```bash
psql -U postgres -h localhost -d quickfund_db -t -A -f portfolio-4-nosql/00_export_customer_ids.sql -o portfolio-4-nosql/customer_ids.js
mongosh $env:MONGODB_URI --file portfolio-4-nosql/01_schema_validation.js
mongosh $env:MONGODB_URI --file portfolio-4-nosql/02_seed_data.js
mongosh $env:MONGODB_URI --file portfolio-4-nosql/03_crud_and_aggregation.js
mongosh $env:MONGODB_URI --file portfolio-4-nosql/04_indexes_explain.js
mongosh $env:MONGODB_URI --file portfolio-4-nosql/05_own_partial_index.js
```

---

## 10. Evidence

| Screenshot | What it shows |
|---|---|
| `01_schema_validation.png` | Creation of `kyc_profiles`, `audit_events`, and `login_sessions` with schema validators, and proof that an invalid document was rejected with error code 121. |
| `02_seed_verification.png` | Output verifying exact seed counts: 5,000 KYC profiles and 100,000 audit events, broken down by event type. |
| `03_crud_output.png` | Execution of CRUD operations: inserting nested documents, array filters, `$set`/`$push` updates, and document deletion. |
| `04_aggregation_output.png` | Results of the four aggregation pipelines (30-day event distribution, daily transfer amounts, `$lookup` join, and documents per tier). |
| `05_indexes_explain.png` | Execution plans before and after index creation, demonstrating the shift from `COLLSCAN` to `IXSCAN` across Q1, Q2, and Q3. |
| `06_ttl_result.png` | Verification that MongoDB's background TTL thread successfully purged the expired session from `login_sessions`. |
| `07_compass_kyc_document.png` | MongoDB Compass interface displaying a seeded KYC profile document with embedded identity documents and UUID customer ID. |
| `08_compass_audit_event.png` | MongoDB Compass interface displaying a seeded audit event document with nested details. |
| `11_own_work.png` | Performance comparison and index size stats showing the 72 KB partial index achieving 1 ms query latency. |

---

## 11. Reflection
Building Portfolio 4 provided practical clarity on the concept of **Polyglot Persistence**. Earlier in the course, the database choice felt like an either-or debate between relational SQL and NoSQL document stores. This implementation showed how both models complement each other in an enterprise fintech architecture. 

PostgreSQL remains the source of truth for all money movement because financial ledgers cannot compromise on ACID guarantees, row-level locks, and strict double-entry balancing. However, trying to force semi-structured KYC verification documents or 100,000 append-only audit logs into PostgreSQL would require either complex multi-table joins or sparse null-heavy tables. 

MongoDB provided the flexibility needed for polymorphic documents and high-volume event logging. At the same time, this portfolio demonstrated that NoSQL does not mean "no rules": using JSON Schema validation, strict UUID pattern enforcement, and compound B-Tree indexes is essential to prevent a document store from degrading into an unmaintainable data swamp. Designing the partial index for fraud flags was especially rewarding, illustrating that understanding query workload distribution can cut storage consumption by over 90% without sacrificing speed.

---

## 12. AI-use declaration
I partially used the Antigravity AI to adapt the reference scripts to my QuickFund schema (UUID customer ids), to explain errors, and to draft the partial index script. I ran every script myself, took every screenshot, and wrote the explanations myself. I checked results by running each script against my own Atlas cluster and reading the output.

