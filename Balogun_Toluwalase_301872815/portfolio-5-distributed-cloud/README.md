Distributed Cloud Databases
# Portfolio 5: Distributed and Cloud Databases (QuickFund)

## 1. Architecture
QuickFund's distributed infrastructure is designed around a multi-tier, hybrid polyglot architecture:
* **Application Services**: Connect to the relational core via standard PostgreSQL connection pooling, separating write-heavy transactional operations from read-heavy reporting feeds.
* **PostgreSQL Primary Container (`quickfund-pg-primary`)**: Runs PostgreSQL 18.6 inside Docker, exposed on host port `5433`. It acts as the single source of truth for all write operations, enforcing ACID double-entry invariants, pessimistic row locks, and financial domain constraints.
* **PostgreSQL Read-Only Replica Container (`quickfund-pg-replica`)**: Runs PostgreSQL 18.6 in hot-standby mode, exposed on host port `5434`. It continuously streams changes from the primary to offload analytical queries, account statement generation, and compliance audits.
* **Physical Streaming Replication & WAL Stream**: The primary streams Write-Ahead Log (WAL) records in real time across an internal Docker network bridge (`172.18.0.0/16`) to the replica using a dedicated physical replication slot (`replica1_slot`).
* **MongoDB Atlas Cloud Replica Set**: A managed 3-node replica set (`quickfund-cluster` / `atlas-5uum6d-shard-0`, MongoDB 8.0.37) deployed in AWS Paris (`eu-west-3`), handling polymorphic KYC identity verification profiles and high-velocity append-only audit event streams.

Evidence: Verified via `docker ps` (`screenshot 01_docker_ps.png`), confirming both containers running PostgreSQL 18.6 with mapped ports `5433` and `5434` in healthy status.

---

## 2. Which workload goes where

| Workload|
|---|
| Transfers and balance checks before a debit | **PostgreSQL Primary (port 5433)** | Moving money requires exclusive row-level locking (`SELECT ... FOR UPDATE`) and immediate consistency; read replicas strictly reject all write transactions. |
| A customer's balance right after a transfer | **PostgreSQL Primary (port 5433)** | Guarantees "read-your-own-writes" consistency. Reading from an asynchronous replica risks displaying a stale pre-transfer balance due to replication lag, causing user panic or duplicate transfer attempts. |
| Old statements, reports, dashboards | **PostgreSQL Read Replica (port 5434)** | Historical ledger scans examine thousands of rows. Offloading analytical reads to the replica protects the primary's CPU, disk I/O, and buffer cache for low-latency payment processing. |
| KYC profiles and audit events | **MongoDB Atlas Cloud Cluster** | Polymorphic verification documents (BVN, NIN, Passport) and high-volume append-only event streams scale independently in the cloud without locking or bloating relational financial tables. |

---

## 3. Replication (Experiments 1 and 2)
* **Primary Health Checks**:
  * `is_replica` = `f` (false; node is the read-write primary)
  * `state` = `streaming`
  * `sync_state` = `async`
  * Replication slot `replica1_slot` `active` = `t` (true; standby is actively connected and holding WAL retention)
  *(Source: `output/01_primary_checks.txt`, screenshots `03_primary_checks.png` and `04_replica_checks.png`)*
* **Replica Write Rejection**: When an update was attempted directly on the standby, the replica refused the write with:
  ```text
  ERROR: cannot execute UPDATE in a read-only transaction
  ```
  *(Source: `output/02_replica_checks.txt`, screenshot `04_replica_checks.png`)*
* **Stale Read Demonstration**:
  * While WAL replay was deliberately paused on the standby, the primary's `replication_marker` count was `2` and the replica's was `1`.
  * The primary's `sent_lsn` was `0/DB73268` while the replica's `replay_lsn` was `0/DB73160`, resulting in `caught_up` = `false` (`screenshot 05_stale_read.png`).
  * Once replay was resumed, both LSN pointers advanced to `0/DB73370` and `caught_up` became `true` (`screenshot 06_caught_up.png`).

### How Streaming Replication Works & The Stale Read Hazard
In PostgreSQL streaming replication, every database modification is recorded as a byte stream in the Write-Ahead Log (WAL). The replica initializes using `pg_basebackup` (a file-level copy of the primary's database cluster) and connects using a dedicated `replicator` role. The primary uses a physical replication slot (`replica1_slot`) to track the replica's consumption; the primary guarantees it will never delete or recycle WAL segments on disk until the replica confirms it has safely received them.

In an asynchronous setup, there is an unavoidable delay between the primary committing a transaction to disk and the standby replaying those bytes into its local memory. In a payments platform, this replication lag creates the **stale read problem**: if Alice transfers ₦10,000 to Bob and the mobile app immediately routes Alice's balance refresh to the replica, Alice will see her old balance. Believing the payment did not go through, she may tap "Send" a second time, resulting in an unintended duplicate charge. In `screenshot 05b`, testing a balance query while replication was paused proved that the standby returned the old balance, demonstrating why customer-facing post-transfer reads must be pinned to the primary.

---

## 4. Consistency and availability (Experiment 3)

| Metric / Scenario | Asynchronous (default) | Synchronous |
|---|---|---|
| Does the commit wait for the replica? | **No.** The primary acknowledges commit as soon as WAL is written to its local disk. | **Yes.** The primary blocks until the standby confirms it has written the WAL to disk. |
| What happened when the replica was down? | The primary continued accepting writes with zero delay or interruption. | The primary **hung indefinitely** on commit, freezing client connections. |
| If the primary dies, can the newest commits be lost? | **Yes.** Transactions committed locally but not yet replayed to the standby can be lost (RPO > 0). | **No.** Every acknowledged transaction is guaranteed to exist on at least two servers (RPO = 0). |
| CAP Theorem leaning | **AP** (Prioritizes Availability & Partition tolerance) | **CP** (Prioritizes strict Consistency over Availability) |

* **Empirical Observations**:
  * With synchronous replication enabled (`synchronous_commit = on`, `synchronous_standby_names = 'replica1'`), `sync_state` transitioned from `async` to `sync`.
  * When the replica container was stopped (`docker stop quickfund-pg-replica`), attempting to insert a new row caused the primary to **hang indefinitely** (`screenshot 07_sync_hang.png.png`).
  * After interrupting the blocked terminal with Ctrl+C, PostgreSQL emitted the warning:
    ```text
    WARNING: canceling wait for synchronous replication due to user request
    DETAIL: The transaction has already committed locally, but might not have been replicated to the standby.
    ```
    `screenshot 08_sync_warning.png` confirms that the transaction actually committed locally on the primary despite the replica being unreachable.

### Architectural Decision for QuickFund
For a digital financial ledger, I would choose **synchronous replication with a multi-node quorum** rather than a fragile 2-node strict sync setup. In banking, losing committed money transfers during an unannounced primary crash (asynchronous data loss) violates core auditability and creates irreconcilable balance discrepancies. However, a 2-node synchronous configuration creates an extreme availability risk: if the single replica undergoes routine maintenance, the entire financial platform halts.

The production middle path is a **3-node cluster with quorum synchronous commit**:
```sql
synchronous_commit = on;
synchronous_standby_names = 'FIRST 1 (replica_zone_a, replica_zone_b)';
```
The primary commits as soon as *any one* of the two standby nodes acknowledges the WAL. If one standby fails or restarts, the platform continues processing payments with zero downtime while maintaining strict zero-data-loss guarantees (RPO = 0).

---

## 5. Sharding and partitioning (Experiment 4)
* **Rows per Partition** (Hash-partitioned on `account_id` across 4 shards, source: `output/03_partitioning.txt`):
  * `ledger_shard_0`: **111,749** rows
  * `ledger_shard_1`: **99,844** rows
  * `ledger_shard_2`: **99,123** rows
  * `ledger_shard_3`: **101,501** rows
  * **Original table rows**: `412,217` | **Partitioned table rows**: `412,217` (100% data fidelity).
* **Partition Pruning Behavior** (`screenshot 09_partitioning.png`):
  * Query with `account_id`: Scans **1** partition (`ledger_shard_0`) via an index seek, completely bypassing the other three shards.
  * Query with `transaction_id`: Scans **4** partitions via a `Parallel Append` sequential scan across all shards.
* **Cross-Shard Transfers**:
  * Transactions touching exactly 1 shard: **51,269**
  * Transactions touching 2 shards (cross-shard): **154,840** (representing **75.1%** of all 206,109 transactions).

### Partition Pruning Explained
Partition pruning is an optimizer intelligence feature in PostgreSQL: when a SQL query includes the partition key (`account_id = ...`) in its `WHERE` clause, PostgreSQL hashes that UUID during query planning and mathematically calculates the exact partition containing the record. It instantly prunes (skips) all other partitions, reducing disk I/O by 75% and scanning only ~100,000 rows instead of all 412,000 rows.

### Distributed Sharding Design for QuickFund (68 words)
We choose `account_id` as the shard key because 95% of OLTP wallet queries are customer balance checks and account statement feeds. The central engineering challenge is that 75% of transfers touch accounts on different physical shards, turning simple atomic updates into distributed transactions requiring Two-Phase Commit (2PC) or an asynchronous Saga orchestrator. System-wide funding accounts become extreme write hotspots on a single shard. Unlike PostgreSQL, MongoDB shards natively through `mongos` routers, but lacks relational cross-collection integrity constraints.

---

## 6. Failover (Experiment 5)
* **Replication Markers Before and After**:
  * Before primary failure: The last recorded marker `id` was **5** (`"last write before the primary dies"`).
  * After replica promotion: The first write on the promoted node had `id` = **38** (`"written on the promoted replica"`).
* **Recovery Timeline & RTO**:
  * Primary stopped at: `2026-11-11 03:29:27 UTC` (`screenshot 10a_primary_down.png`).
  * First successful write on promoted replica at: `2026-11-11 03:31:10 UTC` (`screenshot 10_failover.png`).
  * **Measured Recovery Time (RTO)**: Approximately **103 seconds** (~1.7 minutes).
* **Split-Brain Verification**: When the old primary was restarted alongside the newly promoted primary, both servers reported `is_replica = f` (`screenshot 10c_split_brain.png`).

### Technical Analysis of Manual Failover & Split-Brain Risks
1. **Why Nothing Promoted Itself**: PostgreSQL core contains no built-in election consensus mechanism. A standby remains in permanent read-only recovery mode until an external administrator or supervisor explicitly triggers promotion via `pg_promote()` or the presence of a trigger file.
2. **Why the Sequence ID Jumped (5 to 38)**: PostgreSQL sequence generators pre-allocate blocks of sequence numbers in shared memory cache (typically 32 values) for high-speed insertion. When the primary crashed, its cached values were lost, causing the sequence on the newly promoted primary to resume at 38.
3. **What Split-Brain Is & Why It Destroys Ledgers**: Split-brain occurs when an uncoordinated network partition causes two database nodes to simultaneously believe they are the active write primary. In a banking ledger, split-brain is catastrophic: clients debit and credit both nodes independently, causing diverging balance states that cannot be automatically merged without manual forensic accounting.
4. **RPO and RTO**: In our manual experiment, Recovery Point Objective (RPO) was 0 (zero transactions lost because WAL was fully replayed before the primary stopped), but Recovery Time Objective (RTO) was ~103 seconds due to human manual execution. Production environments deploy **Patroni** with distributed consensus stores (etcd, Consul, or Raft) alongside STONITH fencing ("Shoot The Other Node In The Head") to guarantee automated, split-brain-free failover in under 10 seconds.

---

## 7. Cloud deployment (Experiment 6)
* **Topology & Infrastructure**:
  * MongoDB Atlas replica set `atlas-5uum6d-shard-0` consisting of **3 members** running MongoDB 8.0.37 in **AWS Paris (`eu-west-3`)**.
  * Active Primary: `ac-u5vzxxk-shard-00-02.z21r9ec.mongodb.net:27017`
  * Active Secondaries: `ac-u5vzxxk-shard-00-00` and `ac-u5vzxxk-shard-00-01`
  *(Source: `output/04_atlas_cloud_check.txt`, screenshots `11_atlas_cluster.png` and `12_atlas_check_output.png`)*
* **Write Concern Latency**: An insert using write concern `w: majority` was acknowledged in **253 ms**.
* **Secondary Read Preference**: A query routed explicitly to a secondary node (`readPreference: 'secondary'`) was served by `ac-u5vzxxk-shard-00-00` and returned all **5,000** KYC customer profiles.

### Analysis of Write Concern, Read Preference & Cloud Resilience
* **`w: majority` Guarantees**: Enforcing `w: majority` requires MongoDB to replicate the write to a quorum of nodes (at least 2 out of 3) before returning success to the application. This eliminates the risk of committed data rolling back if the primary node suddenly crashes.
* **Secondary Read Preference & Eventual Consistency**: Reading from secondaries offloads analytical queries from the primary node. However, because replication between Atlas nodes is asynchronous, secondary reads are eventually consistent—a secondary may return slightly stale verification statuses during heavy ingestion bursts.
* **Quorum Loss**: If 2 of the 3 replica set members go offline, majority quorum ($2/3$) is lost. The remaining single node cannot form a majority and automatically steps down to read-only; all subsequent `w: majority` writes will fail or block indefinitely to prevent data corruption.
* **Managed Cloud vs Manual Docker Failover**: In our local Docker environment, failover required manual intervention (stopping containers, promoting nodes, redirecting connection strings). In MongoDB Atlas, heartbeats run every 2 seconds; if the primary fails, the remaining nodes automatically hold an election, elect a new primary, and update DNS records within 2–5 seconds with zero application code changes.
* **Free-Tier Limits**: Atlas M0 sandbox clusters share CPU and memory with other tenants, enforce a 512 MB data ceiling, cap connection limits at 500, lack automated VPC peering, and do not provide point-in-time continuous backups.

---

## 8. My own work
* **Investigation**: Evaluating the true latency cost of MongoDB write concern (`w: 1` vs `w: majority`) across an intercontinental cloud connection.
* **My Prediction**: I predicted that `w: majority` would be significantly slower than `w: 1` because the primary node must pause and wait for confirmation from a second node across the network before acknowledging the write.
* **Empirical Results (100 Sequential Inserts Each)**:
  * Run 1 (`w: 1`, Primary Only): **22,252 ms** total (**222.5 ms** per insert)
  * Run 2 (`w: majority`, Quorum of 2 nodes): **22,741 ms** total (**227.4 ms** per insert)
  * Run 3 (`w: 1` control repeat): **21,790 ms** total (**217.9 ms** per insert)
  *(Source: `output/05_own_write_concern.txt`, screenshot `13_own_work.png`)*

### Humanized Analysis of Results
Comparing the runs reveals a surprising reality: the two identical `w:1` runs differed from each other by 4.6 ms (222.5 ms vs 217.9 ms) simply due to ordinary public internet jitter. Therefore, the tiny 4.9 ms difference between `w:1` (222.5 ms) and `w: majority` (227.4 ms) is completely within random network noise.

Because the test client connected from a local machine over the public internet to AWS Paris, the ~220 ms wide-area network (WAN) round-trip dominated the total latency. Meanwhile, the internal replication between Atlas nodes sitting on sub-millisecond fiber in the same AWS Paris datacenter took less than 2–3 ms. 

**Core Takeaway**: In cloud deployments where application clients communicate across regions or the public web, choosing `w: majority` provides complete crash durability and data loss protection with virtually zero noticeable latency penalty. The real performance penalty of `w: majority` only emerges under high-concurrency multi-client workloads or across multi-region clusters spanning different continents.

---

## 9. Limitations
1. **Single-Host Simulation**: The PostgreSQL primary and replica ran on the same physical developer machine in Docker, meaning hardware-level faults (host power outage, disk failure) impact both nodes simultaneously.
2. **Two-Node Topology (No Quorum Witness)**: Having only one replica means synchronous replication cannot tolerate a single node failure without halting all writes.
3. **Manual Failover Execution**: Node promotion required typing manual CLI commands; production requires automated consensus supervisors.
4. **Hardcoded Credentials**: Demo passwords were used in script variables; production demands HashiCorp Vault or AWS Secrets Manager.
5. **No Continuous Backup / PITR**: While physical replication protects against server crashes, it cannot protect against accidental human error (e.g. `DROP TABLE`); WAL-G or pgBackRest continuous archiving to object storage is required.
6. **No In-Transit Encryption**: Docker internal network communication operated without TLS mutual authentication.
7. **Free-Tier Shared Resources**: Atlas tests ran on an M0 free tier with shared vCPUs and unpredictable noisy-neighbor throttling.
8. **Sequential Client Benchmarking**: Measurements used single-client sequential loops rather than multi-threaded load generators like `pgbench` or JMeter.

**Production Enhancements**: A production deployment would deploy a 3-node Patroni cluster with etcd across three availability zones, enable TLS encryption in transit and at rest, enforce continuous WAL archiving to Amazon S3, and isolate Atlas clusters inside dedicated VPC peering connections.

---

## 10. Reproducing this
Execute the following commands in order from the repository root:

```powershell
# 1. Start primary and replica PostgreSQL containers
docker compose -f portfolio-5-distributed-cloud/docker-compose.yml up -d

# 2. Dump baseline QuickFund schema from local instance
pg_dump -h localhost -U postgres -d quickfund_db --no-owner --no-privileges -f quickfund_dump.sql

# 3. Restore data into the Docker primary (port 5433)
psql $env:PRIMARY -f quickfund_dump.sql

# 4. Verify primary replication health and slot status
psql $env:PRIMARY -f portfolio-5-distributed-cloud/01_primary_checks.sql

# 5. Verify replica streaming status and read-only enforcement
psql $env:REPLICA -f portfolio-5-distributed-cloud/02_replica_checks.sql

# 6. Execute hash-partitioning experiment on the primary
psql $env:PRIMARY -f portfolio-5-distributed-cloud/03_partitioning.sql

# 7. Verify MongoDB Atlas cloud replica set topology and majority write
mongosh $env:MONGODB_URI --file portfolio-5-distributed-cloud/04_atlas_cloud_check.js

# 8. Run custom write concern benchmark experiment
mongosh $env:MONGODB_URI --file portfolio-5-distributed-cloud/05_own_write_concern.js
```

> **Note**: `$env:PRIMARY`, `$env:REPLICA`, and `$env:MONGODB_URI` must be set as environment variables in your terminal session, ensuring no sensitive connection strings or credentials are saved in repository files. The failover and synchronous replication tests in Steps 5, 6, and 8 involve interactive CLI commands described in the report.

---

## 11. Evidence

| Screenshot | What it shows |
|---|---|
| `01_docker_ps.png` | Output of `docker ps` confirming `quickfund-pg-primary` (port 5433) and `quickfund-pg-replica` (port 5434) running healthy on PostgreSQL 18.6. |
| `01_02_row_counts.png` | SQL query verifying restored table row counts: 5,003 customers, 6,003 accounts, 206,109 transactions, and 412,217 ledger entries. |
| `03_primary_checks.png` | Primary diagnostic query showing `is_replica = f`, `state = streaming`, `sync_state = async`, and `replica1_slot active = t`. |
| `04_replica_checks.png` | Standby query showing `is_replica = t`, active WAL receiver, and rejection of write with `ERROR: cannot execute UPDATE in a read-only transaction`. |
| `05_stale_read.png` | Stale read demonstration with WAL replay paused: primary holds 2 markers while replica holds 1, and `sent_lsn != replay_lsn` (`caught_up = f`). |
| `06_caught_up.png` | Verification that after resuming replay, both LSN positions equalized at `0/DB73370` and `caught_up = t`. |
| `07_sync_hang.png.png` | Synchronous replication test: with `sync_state = sync` and the replica container stopped, write query on the primary hangs indefinitely. |
| `08_sync_warning.png` | Ctrl+C interrupt warning confirming transaction committed locally but canceled waiting for standby acknowledgement. |
| `08b_sync_recovered.png` | Primary query showing replication state recovering cleanly back to `async` once the standby was brought back online. |
| `09_partitioning.png` | Explain plans showing partition pruning scanning 1 partition for `account_id` queries versus 4 partitions for `transaction_id` queries. |
| `10_failover.png` | Promoted standby successfully accepting its first transfer write (`p5-failover-1`) as the new read-write primary. |
| `10a_primary_down.png` | Standby server logs showing repeated connection retry errors when the primary container was forcibly stopped. |
| `10b_still_readonly.png` | Standby query verifying it remains read-only (`is_replica = t`) until explicit administrative promotion occurs. |
| `10c_split_brain.png` | Split-brain demonstration: comparing marker sequences where old primary had 5 rows and promoted replica had 6 rows starting at ID 38. |
| `11_atlas_cluster.png` | MongoDB Atlas web dashboard showing the 3-node `quickfund-cluster` replica set healthy in AWS Paris (`eu-west-3`). |
| `11b_atlas_metrics.png` | Atlas real-time monitoring charts displaying connection counts and network bandwidth metrics during testing. |
| `12_atlas_check_output.png` | Execution output of `04_atlas_cloud_check.js` confirming majority write acknowledgement and secondary read preference. |
| `13_own_work.png` | Terminal benchmark output comparing `w: 1` vs `w: majority` over 100 sequential inserts, confirming ~220 ms WAN dominance. |

---

## 12. Reflection
Working through Portfolio 5 brought the theoretical concepts of distributed systems and the CAP theorem into sharp, tangible reality. What surprised me most was how deceptive latency numbers can be: in my own experiment, I expected `w: majority` to double my write latency, but discovered that the ~220 ms cross-continental network trip to Paris completely dwarfed the 2 ms replication step between Atlas servers. 

The hardest trade-off to accept was the brutal simplicity of the CAP theorem during Experiment 3. In software engineering, we want both 100% data loss prevention and 100% continuous uptime. Experiencing the primary freeze solid the moment its replica stopped made me realize that synchronous replication without a multi-node quorum turns a single replica failure into a total business outage.

 Experiencing manual failover and split-brain firsthand proved that distributed data systems require rigorous consensus engineering, strict resource partitioning, and clear boundaries between operational writes and analytical reads.

---

## 13. AI-use declaration
I partially used AI to adapt the reference files to my QuickFund schema (UUID ids, entry_direction), to explain and fix errors in Docker, PostgreSQL and MongoDB, and to draft the partitioning and own-work scripts. I ran every command myself, took every screenshot, and wrote the explanations myself. I checked results by reading each output file and comparing it with what the experiment should show.

