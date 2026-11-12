# AI Use Declaration

**Course**: MIT 8103 — Advanced Database Systems  
**Student**: Balogun Toluwalase  
**Student ID**: 301872815  
**Date**: November 2026

---

I want to be upfront and honest about how I used AI tools during this coursework, what I used them for, and how I made sure the work remained genuinely mine.

---

## Tools I Actually Used

- **Antigravity IDE's AI agent** (the main AI assistant I worked with throughout the project)
- **pgAdmin 4** — for running queries, viewing execution plans, and taking screenshots
- **DBeaver** — for browsing the database schema and verifying table structures
- **psql** (PostgreSQL command-line client) — for running scripts, stress tests, and capturing outputs
- **mongosh** (MongoDB Shell) — for running JavaScript scripts against my Atlas cluster
- **MongoDB Compass** — for visually browsing documents and verifying seeded data
- **Docker Desktop** — for running the primary and replica PostgreSQL containers
- **pgbench** — for the concurrent stress tests in Portfolio 3
- **Git / GitHub** — for version control and repository management

---

## What the AI Was Used For — Per Portfolio

### Portfolio 1: Database Design

I came up with the QuickFund concept and developed the 15 business rules myself, although I used AI to help organise the seed data script. I wanted to generate 5,001 customers, 6,001 accounts, 206,101 transactions and 412,201 balanced ledger entries within a single SQL transaction without relying on loops. The AI helped me understand how generate_series() and cross joins could make this possible. However, I made the decisions concerning the database structure, table names, column definitions, constraints and normalisation myself.

### Portfolio 2: Query Optimisation

I developed the initial eleven queries myself, based on the operations I expected a financial platform to perform. I used AI to help me understand some of the EXPLAIN ANALYZE results, particularly what "external merge Disk: 6464kB" meant and why it was occurring. This helped me realise that pre-sorted indexes were needed, rather than relying only on composite indexes. I then designed all seven indexes myself and tested them on my own database to compare the actual results. The AI helped me understand the underlying concepts, but the index design and implementation were my own work.

### Portfolio 3: Transactions and Concurrency

I used AI to help organise the structure of the reverse_transfer() function in 08_own_experiment_reversal.sql. I already had a working transfer_funds() function and understood what the reversal process should achieve, but needed some help with the PL/pgSQL syntax, especially how to handle the NOT_REVERSIBLE error and arrange the status updates correctly. I also used AI to better understand the meaning of "first-committer-wins" under REPEATABLE READ after encountering a serialization error during testing. However, I designed the pgbench scripts, integrity check queries and test scenarios myself.

### Portfolio 4: NoSQL (MongoDB)

AI was particularly helpful in adjusting scripts to work with my database structure. Most MongoDB examples I found online used simple string IDs, whereas my PostgreSQL customers table used UUIDs. I used AI to help modify the seed data script so it could correctly use the existing UUIDs. It also helped me prepare the partial index script (05_own_partial_index.js) after I had already decided what I wanted to investigate. I expected the fraud index to reduce storage usage, so I used the script to test that assumption. However, I built the aggregation pipeline myself, working through the $lookup, $group and $project stages one at a time.

### Portfolio 5: Distributed and Cloud

This portfolio gave me the most trouble with Docker. I used AI to help me understand and resolve some networking issues, particularly why the replica could not initially connect to the primary. The problem turned out to be a missing host.docker.internal reference in the recovery.conf configuration. I also used AI to help draft the partitioning script (03_partitioning.sql) and the write concern benchmark (05_own_write_concern.js). However, I wrote the README structure and explained what each experiment demonstrated after running the tests and reviewing the results myself.

---

## How I Reviewed and Verified Everything

I want to be specific here because I think this is the most important part.

**I ran every single script myself**,I carried out all the tests using my own PostgreSQL database and MongoDB Atlas cluster. I also personally captured the output files stored in each portfolio's output/ directory and the screenshots saved in the respective screenshots/ folders while running the experiments. All the evidence presented is from my actual work; no screenshots were fabricated or taken from other sources.

**I read the output files carefully** I also reviewed the results against what each experiment was expected to demonstrate. For instance, after running the pgbench stress test in Portfolio 3, I executed the integrity check (07_integrity_check.sql) myself and confirmed that the total system balance was still exactly ₦10,000,000,000.00. This was not a result provided by the AI; I verified it directly by running the query and checking the output.

**I corrected real errors the AI produced.** One example occurred in Portfolio 4, where the first seed data script generated new random UUIDs for the MongoDB documents instead of using the actual UUIDs exported from my PostgreSQL customers table. This created a problem because both databases needed matching customer IDs for the cross-system relationship to work. I noticed something was wrong when I ran a $lookup between audit_events and kyc_profiles and got no matching results. After checking a sample customer_id in MongoDB against the exported list, I realised the IDs were different. I explained the issue to the AI, which helped correct the script to use the IDs from customer_ids.js. Identifying the problem, understanding its cause and guiding the correction were all part of my own debugging process.

**I wrote all the analysis, reflection, and README explanations myself.** The AI was not responsible for writing my Portfolio 2 performance analysis, my Portfolio 3 reflection on how ordered locking works in practice, or my Portfolio 5 discussion of the trade-offs involved in the CAP theorem. I wrote these sections myself after completing the experiments, using the results and observations from my actual work to explain what I learned.

**I can explain every script in this repository.** If you asked me what v_first_id := LEAST(v_from_id, v_to_id) does in 01_transfer_function.sql, I would explain that it ensures every transaction locks rows in the same UUID order. This prevents two transactions from locking resources in opposite directions and waiting endlessly for each other, which can cause a deadlock. I understood why this was necessary after testing the function, observing the deadlock when the ordering was not applied, and seeing how the change resolved the problem.
---

## Final Statement

I used AI tools as a support resource while working on this coursework, mainly to clarify technical concepts, save time when researching certain details and generate scripts for testing. However, I reviewed, tested and modified the scripts to suit my database requirements. The analysis, design choices, interpretation of the results and conclusions presented in this portfolio are based on my own understanding and work.

**Use of AI tools does not remove my responsibility for the accuracy, originality, and understanding of this work. I accept full responsibility for every claim, number, and conclusion presented across all five portfolios.**

---

*Balogun Toluwalase — 301872815*

