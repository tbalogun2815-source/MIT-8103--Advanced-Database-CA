-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 1 (Database Design)
-- Script: constraint_tests.sql
-- Description: Constraint and business rule test suite.
--              Formatted to run seamlessly on ANY query tool
--              (pgAdmin Query Tool, DBeaver, DataGrip, VS Code, psql, etc.).
-- ============================================================================

-- ---------- Setup: clean up any existing test data ----------
DELETE FROM customers WHERE email IN ('ada@example.com', 'bo@example.com', 'cascade@example.com', 'invalid.type@example.com');

-- ---------- Setup: valid rows that should be accepted ----------
INSERT INTO customers (first_name, last_name, email, phone, customer_type)
VALUES ('Ada', 'Obi', 'ada@example.com', '08012345678', 'INDIVIDUAL');

INSERT INTO accounts (customer_id, account_number, account_name, balance)
SELECT customer_id, '0123456789', 'Ada Obi Primary Wallet', 500.00
FROM customers WHERE email = 'ada@example.com';

INSERT INTO transactions (idempotency_key, transaction_type, amount, status)
VALUES ('txn-key-001', 'DEPOSIT', 500.00, 'SUCCESS');

INSERT INTO ledger_entries (transaction_id, account_id, entry_direction, amount)
SELECT t.transaction_id, a.account_id, 'CREDIT', 500.00
FROM transactions t, accounts a
WHERE t.idempotency_key = 'txn-key-001' AND a.account_number = '0123456789';


-- ---------- Test 1: balance can never go negative (CHECK) ----------
DO $$
BEGIN
    INSERT INTO accounts (customer_id, account_number, account_name, balance)
    SELECT customer_id, '0123456780', 'Negative Wallet', -1.00
    FROM customers WHERE email = 'ada@example.com';
    RAISE EXCEPTION 'TEST FAILED: negative balance was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 1: negative balance rejected';
END $$;


-- ---------- Test 2: account number must be exactly 10 digits (CHECK) ----------
DO $$
BEGIN
    INSERT INTO accounts (customer_id, account_number, account_name)
    SELECT customer_id, '12AB', 'Bad Account'
    FROM customers WHERE email = 'ada@example.com';
    RAISE EXCEPTION 'TEST FAILED: malformed account number was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 2: malformed account number rejected';
END $$;


-- ---------- Test 3: a transaction amount must be positive (CHECK) ----------
DO $$
BEGIN
    INSERT INTO transactions (idempotency_key, transaction_type, amount)
    VALUES ('txn-key-zero', 'TRANSFER', 0.00);
    RAISE EXCEPTION 'TEST FAILED: zero-amount transaction was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 3: zero-amount transaction rejected';
END $$;


-- ---------- Test 4: a REVERSAL must reference an original (CHECK) ----------
DO $$
BEGIN
    INSERT INTO transactions (idempotency_key, transaction_type, amount, reversal_of)
    VALUES ('txn-key-rev', 'REVERSAL', 10.00, NULL);
    RAISE EXCEPTION 'TEST FAILED: reversal without an original was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 4: reversal without original rejected';
END $$;


-- ---------- Test 5: email must be unique (UNIQUE) ----------
DO $$
BEGIN
    INSERT INTO customers (first_name, last_name, email, phone, customer_type)
    VALUES ('Bo', 'Eze', 'ada@example.com', '08099999999', 'MERCHANT');
    RAISE EXCEPTION 'TEST FAILED: duplicate email was accepted';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS 5: duplicate email rejected';
END $$;


-- ---------- Test 6: idempotency key stops a double-applied request (UNIQUE) ----------
DO $$
BEGIN
    INSERT INTO transactions (idempotency_key, transaction_type, amount)
    VALUES ('txn-key-001', 'DEPOSIT', 500.00);
    RAISE EXCEPTION 'TEST FAILED: repeated idempotency key was accepted';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS 6: repeated idempotency key rejected';
END $$;


-- ---------- Test 7: an account needs a real customer (FOREIGN KEY) ----------
DO $$
BEGIN
    INSERT INTO accounts (customer_id, account_number, account_name)
    VALUES ('00000000-0000-0000-0000-000000000000'::uuid, '1111111111', 'Ghost Customer Account');
    RAISE EXCEPTION 'TEST FAILED: account for a missing customer was accepted';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'PASS 7: account for unknown customer rejected';
END $$;


-- ---------- Test 8: a customer with accounts cannot be deleted (ON DELETE RESTRICT) ----------
DO $$
BEGIN
    DELETE FROM customers WHERE email = 'ada@example.com';
    RAISE EXCEPTION 'TEST FAILED: customer with financial history was deleted';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'PASS 8: deleting a customer with accounts is blocked';
END $$;


-- ---------- Test 9: fraud risk score must be 0 to 100 (CHECK) ----------
DO $$
BEGIN
    INSERT INTO fraud_flags (transaction_id, risk_score, risk_level, reason)
    SELECT transaction_id, 105, 'CRITICAL', 'Score out of range test'
    FROM transactions WHERE idempotency_key = 'txn-key-001';
    RAISE EXCEPTION 'TEST FAILED: risk score > 100 was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 9: out-of-range risk score rejected';
END $$;


-- ---------- Test 10: customer type must be INDIVIDUAL or MERCHANT (CHECK) ----------
DO $$
BEGIN
    INSERT INTO customers (first_name, last_name, email, phone, customer_type)
    VALUES ('Invalid', 'Type', 'invalid.type@example.com', '08088888888', 'CORPORATE');
    RAISE EXCEPTION 'TEST FAILED: invalid customer type was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 10: invalid customer type rejected';
END $$;


-- ---------- Test 11: KYC verification timestamp requires non-PENDING status (CHECK) ----------
DO $$
BEGIN
    INSERT INTO kyc_records (customer_id, tier_level, id_type, id_number, status, verified_at)
    SELECT customer_id, 1, 'NIN', '12345678901', 'PENDING', CURRENT_TIMESTAMP
    FROM customers WHERE email = 'ada@example.com';
    RAISE EXCEPTION 'TEST FAILED: PENDING KYC with verified_at was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 11: PENDING KYC with verification timestamp rejected';
END $$;


-- ---------- Test 12: card last four must be 4 numeric digits (CHECK) ----------
DO $$
BEGIN
    INSERT INTO cards (account_id, card_token, last_four, card_type, card_brand, expiry_month, expiry_year, cardholder_name)
    SELECT account_id, 'tok-test-bad-last4', '432A', 'DEBIT', 'MASTERCARD', 12, 2028, 'Ada Obi'
    FROM accounts WHERE account_number = '0123456789';
    RAISE EXCEPTION 'TEST FAILED: alphanumeric card last_four was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 12: invalid card last_four digits rejected';
END $$;


-- ---------- Test 13: non-reversal transaction must not reference an original (CHECK) ----------
DO $$
BEGIN
    INSERT INTO transactions (idempotency_key, transaction_type, amount, reversal_of)
    SELECT 'txn-key-bad-rev', 'TRANSFER', 50.00, transaction_id
    FROM transactions WHERE idempotency_key = 'txn-key-001';
    RAISE EXCEPTION 'TEST FAILED: non-reversal referencing another transaction was accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS 13: non-reversal with original reference rejected';
END $$;


-- ---------- Test 14: account cannot appear twice in same direction in one transaction (UNIQUE) ----------
DO $$
BEGIN
    INSERT INTO ledger_entries (transaction_id, account_id, entry_direction, amount)
    SELECT t.transaction_id, a.account_id, 'CREDIT', 200.00
    FROM transactions t, accounts a
    WHERE t.idempotency_key = 'txn-key-001' AND a.account_number = '0123456789';
    RAISE EXCEPTION 'TEST FAILED: duplicate ledger entry direction for same account was accepted';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS 14: duplicate direction for account in transaction rejected';
END $$;


-- ---------- Test 15: beneficiary is deleted when customer is deleted (CASCADE) ----------
DO $$
DECLARE
    v_cust_id UUID;
    v_bene_count INT;
BEGIN
    INSERT INTO customers (first_name, last_name, email, phone, customer_type)
    VALUES ('Cascade', 'User', 'cascade@example.com', '08077777777', 'INDIVIDUAL')
    RETURNING customer_id INTO v_cust_id;

    INSERT INTO beneficiaries (customer_id, beneficiary_account_number, bank_name, account_name)
    VALUES (v_cust_id, '9988776655', 'Zenith Bank', 'Recipient Name');

    DELETE FROM customers WHERE customer_id = v_cust_id;

    SELECT COUNT(*) INTO v_bene_count
    FROM beneficiaries
    WHERE customer_id = v_cust_id;

    IF v_bene_count != 0 THEN
        RAISE EXCEPTION 'TEST FAILED: beneficiary was not cascaded upon customer deletion';
    END IF;

    RAISE NOTICE 'PASS 15: customer deletion cascades to beneficiaries';
END $$;
