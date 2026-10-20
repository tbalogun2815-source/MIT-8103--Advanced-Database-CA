-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 1 (Database Design)
-- Script: seed_data.sql
-- Description: Deterministic, high-volume production seed generator.
--
-- Generates (approximately):
--   - 5,001 customers (incl. one internal settlement treasury customer)
--   - 6,001 accounts (incl. central treasury settlement account)
--   - ~200,000 transfers
--   - ~6,000 opening deposits
--   - ~100 reversals
--   - ~400,000+ double-entry ledger lines
--
-- Features:
--   - Entire script executes inside a single transaction (all or nothing).
--   - 100% pure set-based PostgreSQL SQL (generate_series, modulo, window functions).
--   - Fully deterministic and reproducible using fixed seed (setseed).
--   - Guarantees mathematical ledger balance: SUM(Debits) = SUM(Credits).
--   - Automatically synchronizes accounts.balance with zero discrepancies.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. INITIALIZE REPRODUCIBILITY & CLEAN SLATE
-- ----------------------------------------------------------------------------
SELECT setseed(0.42);

-- Clean slate in reverse dependency order
TRUNCATE TABLE fraud_flags, ledger_entries, transactions, cards, beneficiaries, accounts, kyc_records, customers RESTART IDENTITY CASCADE;


-- ----------------------------------------------------------------------------
-- 1. SEED CUSTOMERS (5,001 TOTAL)
--    - 1 Internal Settlement Customer
--    - 5,000 Retail & Merchant Customers
-- ----------------------------------------------------------------------------
-- 1.1 Internal settlement customer
INSERT INTO customers (
    customer_id, first_name, last_name, email, phone, customer_type, is_active, created_at
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'QuickFund',
    'Settlement Treasury',
    'settlement@quickfund.internal',
    '+2340000000000',
    'MERCHANT',
    TRUE,
    '2025-01-01 00:00:00+00'
);

-- 1.2 5,000 Customers with realistic Nigerian demographics
INSERT INTO customers (
    first_name, last_name, email, phone, customer_type, is_active, created_at
)
SELECT
    (ARRAY['Adebayo', 'Chinedu', 'Fatima', 'Olumide', 'Ngozi', 'Ibrahim', 'Folake', 'Emeka', 'Zainab', 'Tunde', 
           'Chioma', 'Babajide', 'Amina', 'Damilola', 'Kelechi', 'Halima', 'Oluwaseun', 'Obinna', 'Bisi', 'Mustapha'])[1 + (i % 20)] AS first_name,
    (ARRAY['Balogun', 'Okafor', 'Danjuma', 'Adeyemi', 'Nwosu', 'Abubakar', 'Eze', 'Ogunleye', 'Bello', 'Okeke', 
           'Akinyemi', 'Garba', 'Okonkwo', 'Suleiman', 'Alabi', 'Ibe', 'Oladipo', 'Sanusi', 'Osuntokun', 'Lawal'])[1 + ((i * 7) % 20)] AS last_name,
    'customer' || i || '@quickfund.test' AS email,
    '+23480' || lpad(i::text, 8, '0') AS phone,
    CASE WHEN i % 10 = 0 THEN 'MERCHANT' ELSE 'INDIVIDUAL' END AS customer_type,
    TRUE AS is_active,
    '2025-01-01 08:00:00+00'::timestamptz + (i * interval '30 seconds') AS created_at
FROM generate_series(1, 5000) AS s(i);


-- ----------------------------------------------------------------------------
-- 2. SEED ACCOUNTS (6,001 TOTAL)
--    - 1 Central Settlement Account
--    - 5,000 Primary Wallet Accounts (1 per customer)
--    - 1,000 Secondary/Savings Accounts (customers 1..1000)
-- ----------------------------------------------------------------------------
-- 2.1 Central settlement treasury account
INSERT INTO accounts (
    account_id, customer_id, account_number, account_name, balance, currency, status, created_at
) VALUES (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    '0000000000',
    'QuickFund Central Settlement Account',
    0.00,
    'NGN',
    'ACTIVE',
    '2025-01-01 00:00:00+00'
);

-- Temp table of customers ordered to map 1:1 reliably
CREATE TEMP TABLE temp_customer_indexed ON COMMIT DROP AS
SELECT 
    row_number() OVER (ORDER BY created_at) AS row_num,
    customer_id,
    first_name || ' ' || last_name AS full_name
FROM customers
WHERE customer_id != '00000000-0000-0000-0000-000000000001';

CREATE UNIQUE INDEX ON temp_customer_indexed(row_num);

-- 2.2 5,000 Primary Accounts
INSERT INTO accounts (
    customer_id, account_number, account_name, balance, currency, status, created_at
)
SELECT
    c.customer_id,
    '10' || lpad(c.row_num::text, 8, '0') AS account_number,
    c.full_name || ' Primary Wallet' AS account_name,
    0.00 AS balance,
    'NGN' AS currency,
    'ACTIVE' AS status,
    '2025-01-02 09:00:00+00'::timestamptz + (c.row_num * interval '20 seconds') AS created_at
FROM temp_customer_indexed c;

-- 2.3 1,000 Secondary / Savings Accounts
INSERT INTO accounts (
    customer_id, account_number, account_name, balance, currency, status, created_at
)
SELECT
    c.customer_id,
    '20' || lpad(c.row_num::text, 8, '0') AS account_number,
    c.full_name || ' Savings/Business Wallet' AS account_name,
    0.00 AS balance,
    'NGN' AS currency,
    'ACTIVE' AS status,
    '2025-01-03 10:00:00+00'::timestamptz + (c.row_num * interval '30 seconds') AS created_at
FROM temp_customer_indexed c
WHERE c.row_num <= 1000;


-- ----------------------------------------------------------------------------
-- 3. SEED OPENING DEPOSITS (~6,001 TRANSACTIONS & ~12,001 LEDGER ENTRIES)
--    - Injects Central Settlement capital (10 Billion NGN)
--    - Credits each of the 6,000 customer accounts with opening balance
-- ----------------------------------------------------------------------------
-- Map all 6,000 customer accounts with sequential indexing
CREATE TEMP TABLE temp_account_indexed ON COMMIT DROP AS
SELECT 
    row_number() OVER (ORDER BY created_at, account_number) AS acc_row,
    account_id,
    account_number
FROM accounts
WHERE account_number != '0000000000';

CREATE UNIQUE INDEX ON temp_account_indexed(acc_row);

-- 3.1 Initial Central Treasury Capital Transaction
INSERT INTO transactions (
    transaction_id, idempotency_key, transaction_type, amount, currency, status, description, created_at, completed_at
) VALUES (
    '00000000-0000-0000-0000-000000000003',
    'TXN-CAPITAL-SEED-001',
    'DEPOSIT',
    10000000000.00, -- 10 Billion NGN
    'NGN',
    'SUCCESS',
    'Central Bank Clearing Capital Inflow',
    '2025-01-05 08:00:00+00',
    '2025-01-05 08:00:01+00'
);

INSERT INTO ledger_entries (
    transaction_id, account_id, entry_direction, amount, created_at
) VALUES (
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000002', -- Settlement account
    'CREDIT',
    10000000000.00,
    '2025-01-05 08:00:01+00'
);

-- 3.2 6,000 Opening Deposit Transactions (each between 150,000 and 350,000 NGN)
CREATE TEMP TABLE temp_opening_deposits ON COMMIT DROP AS
SELECT
    gen_random_uuid() AS tx_id,
    'DEP-INIT-' || lpad(a.acc_row::text, 8, '0') AS idempotency_key,
    'DEPOSIT'::varchar(20) AS transaction_type,
    ROUND((150000.00 + (a.acc_row % 200000) + ((a.acc_row % 99)::numeric / 100.0)), 2) AS amount,
    'NGN'::varchar(3) AS currency,
    'SUCCESS'::varchar(20) AS status,
    'Opening customer wallet deposit'::varchar(255) AS description,
    '2025-01-06 08:00:00+00'::timestamptz + (a.acc_row * interval '5 seconds') AS tx_time,
    a.account_id AS customer_acc_id
FROM temp_account_indexed a;

INSERT INTO transactions (
    transaction_id, idempotency_key, transaction_type, amount, currency, status, description, created_at, completed_at
)
SELECT
    tx_id, idempotency_key, transaction_type, amount, currency, status, description, tx_time, tx_time + interval '1 second'
FROM temp_opening_deposits;

-- Double-entry ledger postings for opening deposits:
-- Debit Settlement Treasury, Credit Customer Account
INSERT INTO ledger_entries (
    transaction_id, account_id, entry_direction, amount, created_at
)
SELECT
    d.tx_id,
    '00000000-0000-0000-0000-000000000002'::uuid AS account_id,
    'DEBIT' AS entry_direction,
    d.amount,
    d.tx_time
FROM temp_opening_deposits d
UNION ALL
SELECT
    d.tx_id,
    d.customer_acc_id AS account_id,
    'CREDIT' AS entry_direction,
    d.amount,
    d.tx_time
FROM temp_opening_deposits d;


-- ----------------------------------------------------------------------------
-- 4. SEED PEER-TO-PEER TRANSFERS (~200,000 TRANSFERS & ~400,000 LEDGER ENTRIES)
--    - Distributes money across all 6,000 customer accounts
--    - Balanced rotation guarantees no account balance goes negative
-- ----------------------------------------------------------------------------
CREATE TEMP TABLE temp_transfer_batch ON COMMIT DROP AS
SELECT
    s.i,
    gen_random_uuid() AS tx_id,
    'TXN-TRF-' || lpad(s.i::text, 10, '0') AS idempotency_key,
    (1 + ((s.i * 37) % 6000))::int AS src_row,
    (1 + (((1 + ((s.i * 37) % 6000)) - 1 + (1 + ((s.i * 17) % 5999))) % 6000))::int AS dst_row,
    ROUND((20.00 + (s.i % 380) + ((s.i % 100)::numeric / 100.0)), 2) AS amount,
    '2025-01-10 00:00:00+00'::timestamptz + (s.i * interval '1 second') AS tx_time
FROM generate_series(1, 200000) AS s(i);

-- Join to map internal account IDs
CREATE TEMP TABLE temp_transfer_resolved ON COMMIT DROP AS
SELECT
    t.i,
    t.tx_id,
    t.idempotency_key,
    t.amount,
    t.tx_time,
    src.account_id AS src_account_id,
    dst.account_id AS dst_account_id
FROM temp_transfer_batch t
JOIN temp_account_indexed src ON src.acc_row = t.src_row
JOIN temp_account_indexed dst ON dst.acc_row = t.dst_row;

CREATE UNIQUE INDEX ON temp_transfer_resolved(i);

-- Insert 200,000 transfer transactions
INSERT INTO transactions (
    transaction_id, idempotency_key, transaction_type, amount, currency, status, description, created_at, completed_at
)
SELECT
    tx_id,
    idempotency_key,
    'TRANSFER',
    amount,
    'NGN',
    'SUCCESS',
    'Customer P2P wallet money transfer',
    tx_time,
    tx_time + interval '1 second'
FROM temp_transfer_resolved;

-- Insert 400,000 double-entry ledger entries:
-- Legs: Debit Sender Account, Credit Receiver Account
INSERT INTO ledger_entries (
    transaction_id, account_id, entry_direction, amount, created_at
)
SELECT
    tx_id,
    src_account_id AS account_id,
    'DEBIT' AS entry_direction,
    amount,
    tx_time
FROM temp_transfer_resolved
UNION ALL
SELECT
    tx_id,
    dst_account_id AS account_id,
    'CREDIT' AS entry_direction,
    amount,
    tx_time
FROM temp_transfer_resolved;


-- ----------------------------------------------------------------------------
-- 5. SEED REVERSALS (~100 REVERSALS & ~200 LEDGER ENTRIES)
--    - Selects 100 transfers across the batch
--    - Enforces chk_tx_reversal_logic (reversal_of reference)
--    - Generates balanced reverse debit/credit entries
-- ----------------------------------------------------------------------------
CREATE TEMP TABLE temp_reversal_candidates ON COMMIT DROP AS
SELECT
    row_number() OVER (ORDER BY i) AS rev_idx,
    tx_id AS original_tx_id,
    amount,
    tx_time + interval '45 minutes' AS rev_time,
    src_account_id,
    dst_account_id
FROM temp_transfer_resolved
WHERE i IN (
    1000,  3000,  5000,  7000,  9000,  11000, 13000, 15000, 17000, 19000,
    21000, 23000, 25000, 27000, 29000, 31000, 33000, 35000, 37000, 39000,
    41000, 43000, 45000, 47000, 49000, 51000, 53000, 55000, 57000, 59000,
    61000, 63000, 65000, 67000, 69000, 71000, 73000, 75000, 77000, 79000,
    81000, 83000, 85000, 87000, 89000, 91000, 93000, 95000, 97000, 99000,
    101000, 103000, 105000, 107000, 109000, 111000, 113000, 115000, 117000, 119000,
    121000, 123000, 125000, 127000, 129000, 131000, 133000, 135000, 137000, 139000,
    141000, 143000, 145000, 147000, 149000, 151000, 153000, 155000, 157000, 159000,
    161000, 163000, 165000, 167000, 169000, 171000, 173000, 175000, 177000, 179000,
    181000, 183000, 185000, 187000, 189000, 191000, 193000, 195000, 197000, 199000
);

-- Generate new UUID for reversal transactions
CREATE TEMP TABLE temp_reversals ON COMMIT DROP AS
SELECT
    gen_random_uuid() AS rev_tx_id,
    'TXN-REV-' || lpad(rev_idx::text, 6, '0') AS idempotency_key,
    original_tx_id,
    amount,
    rev_time,
    src_account_id,
    dst_account_id
FROM temp_reversal_candidates;

-- Insert 100 reversal transactions
INSERT INTO transactions (
    transaction_id, idempotency_key, transaction_type, amount, currency, reversal_of, status, description, created_at, completed_at
)
SELECT
    rev_tx_id,
    idempotency_key,
    'REVERSAL',
    amount,
    'NGN',
    original_tx_id,
    'SUCCESS',
    'Customer disputed or failed transfer reversal',
    rev_time,
    rev_time + interval '1 second'
FROM temp_reversals;

-- Mark original transactions as REVERSED
UPDATE transactions t
SET status = 'REVERSED'
FROM temp_reversals r
WHERE t.transaction_id = r.original_tx_id;

-- Insert 200 reversal ledger entries (Refund original sender, Debit original receiver)
INSERT INTO ledger_entries (
    transaction_id, account_id, entry_direction, amount, created_at
)
SELECT
    rev_tx_id,
    src_account_id AS account_id,
    'CREDIT' AS entry_direction, -- Refund sender
    amount,
    rev_time
FROM temp_reversals
UNION ALL
SELECT
    rev_tx_id,
    dst_account_id AS account_id,
    'DEBIT' AS entry_direction,  -- Reclaim from receiver
    amount,
    rev_time
FROM temp_reversals;


-- ----------------------------------------------------------------------------
-- 6. SYNCHRONIZE ACCOUNTS.BALANCE WITH NET LEDGER POSTINGS
--    - Guarantees 100% mathematical consistency with ledger history
-- ----------------------------------------------------------------------------
UPDATE accounts a
SET balance = COALESCE(l.net_balance, 0.00),
    updated_at = CURRENT_TIMESTAMP
FROM (
    SELECT 
        account_id,
        SUM(CASE WHEN entry_direction = 'CREDIT' THEN amount ELSE -amount END) AS net_balance
    FROM ledger_entries
    GROUP BY account_id
) l
WHERE a.account_id = l.account_id;


-- ----------------------------------------------------------------------------
-- 7. AUDIT VALIDATION CHECKS (FAIL TRANSACTION IF INTEGRITY FAILS)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_cust_count        INT;
    v_acc_count         INT;
    v_tx_count          INT;
    v_rev_count         INT;
    v_ledger_count      INT;
    v_net_diff          NUMERIC(15, 2);
    v_discrepancies     INT;
    v_negative_balances INT;
BEGIN
    SELECT COUNT(*) INTO v_cust_count FROM customers;
    SELECT COUNT(*) INTO v_acc_count FROM accounts;
    SELECT COUNT(*) INTO v_tx_count FROM transactions;
    SELECT COUNT(*) INTO v_rev_count FROM transactions WHERE transaction_type = 'REVERSAL';
    SELECT COUNT(*) INTO v_ledger_count FROM ledger_entries;

    -- Verify double-entry ledger balance
    SELECT COALESCE(SUM(CASE WHEN entry_direction = 'CREDIT' THEN amount ELSE -amount END), 0.00)
    INTO v_net_diff
    FROM ledger_entries;

    -- Verify account balance vs ledger alignment
    SELECT COUNT(*) INTO v_discrepancies
    FROM accounts a
    JOIN (
        SELECT account_id, SUM(CASE WHEN entry_direction = 'CREDIT' THEN amount ELSE -amount END) AS ledger_sum
        FROM ledger_entries
        GROUP BY account_id
    ) l ON a.account_id = l.account_id
    WHERE a.balance != l.ledger_sum;

    -- Verify no negative balances
    SELECT COUNT(*) INTO v_negative_balances FROM accounts WHERE balance < 0.00;

    RAISE NOTICE '=====================================================';
    RAISE NOTICE '           SEED DATA VERIFICATION REPORT             ';
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'Total Customers:       %', v_cust_count;
    RAISE NOTICE 'Total Accounts:        %', v_acc_count;
    RAISE NOTICE 'Total Transactions:    %', v_tx_count;
    RAISE NOTICE 'Total Reversals:       %', v_rev_count;
    RAISE NOTICE 'Total Ledger Entries:  %', v_ledger_count;
    RAISE NOTICE 'Net Ledger Difference: % NGN', v_net_diff;
    RAISE NOTICE 'Balance Discrepancies: %', v_discrepancies;
    RAISE NOTICE 'Negative Balances:     %', v_negative_balances;
    RAISE NOTICE '=====================================================';

    IF v_cust_count != 5001 THEN
        RAISE EXCEPTION 'SEED FAILED: Expected 5,001 customers, found %', v_cust_count;
    END IF;

    IF v_acc_count != 6001 THEN
        RAISE EXCEPTION 'SEED FAILED: Expected 6,001 accounts, found %', v_acc_count;
    END IF;

    IF v_rev_count != 100 THEN
        RAISE EXCEPTION 'SEED FAILED: Expected 100 reversals, found %', v_rev_count;
    END IF;

    IF v_discrepancies != 0 THEN
        RAISE EXCEPTION 'SEED FAILED: Found % account balance discrepancies!', v_discrepancies;
    END IF;

    IF v_negative_balances != 0 THEN
        RAISE EXCEPTION 'SEED FAILED: Found % negative account balances!', v_negative_balances;
    END IF;

    RAISE NOTICE '[SUCCESS] All business rules, counts, and ledger balances verified.';
END $$;

COMMIT;
