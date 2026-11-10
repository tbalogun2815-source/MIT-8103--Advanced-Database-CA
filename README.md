# MIT-8103: Advanced Database Systems - Continuous Assessment

## Overview
This repository contains the complete coursework and continuous assessment implementation for **MIT-8103: Advanced Database Systems**.

## Course Structure & Portfolios
- [Portfolio 1: Database Design & Relational Implementation](MIT-8103 Advanced CA project/portfolio-1-database-design/README.md)
  - Core QuickFund relational schema (PostgreSQL), double-entry ledger, constraints, normalisation report, and high-volume seed data.
- [Portfolio 2: Query Optimisation & Performance Tuning](MIT-8103 Advanced CA project/portfolio-2-query-optimisation/performance_analysis.md)
  - Performance audit, indexing strategy, query plans (EXPLAIN ANALYZE), planner selectivity, and write-tax benchmark.
- [Portfolio 3: Transactions, Concurrency & ACID Guarantees](MIT-8103 Advanced CA project/portfolio-3-transactions-concurrency/README.md)
  - Atomic double-entry money transfers, canonical ordered locking, isolation level experiments, deadlock detection, pgbench stress benchmarks, integrity verification, and safe reversals.
- [Portfolio 4: NoSQL Document Storage (MongoDB)](MIT-8103 Advanced CA project/portfolio-4-nosql/README.md)
  - Polyglot persistence, JSON Schema validation, embedded KYC profiles, 100k audit events stream, compound and TTL indexes, aggregation pipelines, and partial index optimization.
- **Portfolio 5: Distributed & Cloud Databases**

## Directory Tree
```text
MIT-8103--Advanced-Database-CA/
├── README.md
└── MIT-8103 Advanced CA project/
    ├── portfolio-1-database-design/
    │   ├── 00_create_database.sql
    │   ├── case-study.md
    │   ├── create_tables.sql
    │   ├── constraint_tests.sql
    │   ├── normalisation.md
    │   ├── seed_data.sql
    │   ├── screenshots/
    │   └── README.md
    ├── portfolio-2-query-optimisation/
    │   ├── queries/
    │   ├── sql/
    │   ├── plans/
    │   ├── screenshots/
    │   └── performance_analysis.md
    ├── portfolio-3-transactions-concurrency/
    │   ├── 01_transfer_function.sql
    │   ├── 02_demo_setup.sql
    │   ├── 03_commit_rollback_demo.sql
    │   ├── 05_stress_ordered.pgbench
    │   ├── 06_stress_unordered.pgbench
    │   ├── 07_integrity_check.sql
    │   ├── 08_own_experiment_reversal.sql
    │   ├── output/
    │   ├── screenshots/
    │   ├── my_notes.txt
    │   ├── README.md
    │   ├── analysis.md
    │   └── reflection.md
    ├── portfolio-4-nosql/
    │   ├── 00_export_customer_ids.sql
    │   ├── 01_schema_validation.js
    │   ├── 02_seed_data.js
    │   ├── 03_crud_and_aggregation.js
    │   ├── 04_indexes_explain.js
    │   ├── 05_own_partial_index.js
    │   ├── customer_ids.js
    │   ├── output/
    │   ├── screenshots/
    │   └── README.md
    └── portfolio-5-distributed-cloud/
```

## Setup & Prerequisites
- **RDBMS**: PostgreSQL 15+ / 16+
- **Document Store**: MongoDB 6+
- **Tooling**: `psql`, pgAdmin 4, DBeaver, or DataGrip

## Author
- **GitHub**: [@tbalogun2815-source](https://github.com/tbalogun2815-source)
