-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 1 (Database Design)
-- Script: constraint_tests.sql
-- Description: Automated constraint and business rule validation test suite.
--              Executes positive tests and negative tests (boundary and violation)
--              using PL/pgSQL blocks to ensure all domain constraints, checks,
--              unique indexes, and foreign keys enforce data integrity properly.
-- ============================================================================

\set ON_ERROR_STOP on

SELECT '=====================================================' AS test_suite_banner;
SELECT 'STARTING CONSTRAINT AND BUSINESS RULE VALIDATION SUITE' AS test_suite_banner;
SELECT '=====================================================' AS test_suite_banner;

-- ============================================================================
-- SETUP BASE FIXTURES
-- Create valid foundational records for testing downstream constraints.
-- ============================================================================
DO $$
DECLARE
    v_cust_id       UUID;
    v_acc_id        UUID;
    v_tx_id         UUID;
BEGIN
    RAISE NOTICE '--- Setting up test baseline fixtures ---';

    -- 1. Insert valid test customer
    INSERT INTO customers (
        customer_id, first_name, last_name, email, phone, customer_type, is_active
    ) VALUES (
        '11111111-1111-1111-1111-111111111111',
        'Amara', 'Okonkwo',
        'amara.okonkwo@quickfund.test',
        '+2348012345678',
        'INDIVIDUAL',
        TRUE
    ) ON CONFLICT (email) DO NOTHING;

    -- 2. Insert valid test account (10-digit NUBAN, positive balance)
    INSERT INTO accounts (
        account_id, customer_id, account_number, account_name, balance, currency, status
    ) VALUES (
        '22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111',
        '0123456789',
        'Amara Okonkwo Primary Wallet',
        150000.00,
        'NGN',
        'ACTIVE'
    ) ON CONFLICT (account_number) DO NOTHING;

    -- 3. Insert valid test transaction
    INSERT INTO transactions (
        transaction_id, idempotency_key, transaction_type, amount, currency, status, description
    ) VALUES (
        '33333333-3333-3333-3333-333333333333',
        'IDEMP-TEST-BASE-001',
        'DEPOSIT',
        50000.00,
        'NGN',
        'SUCCESS',
        'Initial wallet top-up test'
    ) ON CONFLICT (idempotency_key) DO NOTHING;

    RAISE NOTICE '[PASS] Baseline test fixtures established.';
END $$;


-- ============================================================================
-- TEST SUITE 1: CUSTOMER TABLE CONSTRAINTS
-- ============================================================================

-- Test 1.1: Reject duplicate email
DO $$
BEGIN
    INSERT INTO customers (
        first_name, last_name, email, phone, customer_type
    ) VALUES (
        'Duplicate', 'EmailUser', 'amara.okonkwo@quickfund.test', '+2348099990001', 'INDIVIDUAL'
    );
    RAISE EXCEPTION 'TEST 1.1 FAILED: Duplicate email was permitted.';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE '[PASS] Test 1.1: Duplicate customer email rejected (UNIQUE violation).';
END $$;

-- Test 1.2: Reject duplicate phone number
DO $$
BEGIN
    INSERT INTO customers (
        first_name, last_name, email, phone, customer_type
    ) VALUES (
        'Duplicate', 'PhoneUser', 'different.email@quickfund.test', '+2348012345678', 'INDIVIDUAL'
    );
    RAISE EXCEPTION 'TEST 1.2 FAILED: Duplicate phone number was permitted.';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE '[PASS] Test 1.2: Duplicate customer phone number rejected (UNIQUE violation).';
END $$;

-- Test 1.3: Reject invalid customer_type (Rule: INDIVIDUAL or MERCHANT only)
DO $$
BEGIN
    INSERT INTO customers (
        first_name, last_name, email, phone, customer_type
    ) VALUES (
        'Invalid', 'TypeUser', 'invalid.type@quickfund.test', '+2348099990002', 'GOVERNMENT'
    );
    RAISE EXCEPTION 'TEST 1.3 FAILED: Invalid customer type was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 1.3: Invalid customer_type rejected by chk_customer_type.';
END $$;


-- ============================================================================
-- TEST SUITE 2: KYC RECORDS CONSTRAINTS
-- ============================================================================

-- Test 2.1: Reject PENDING KYC record with non-null verified_at timestamp
DO $$
BEGIN
    INSERT INTO kyc_records (
        customer_id, tier_level, id_type, id_number, status, verified_at
    ) VALUES (
        '11111111-1111-1111-1111-111111111111',
        1,
        'NIN',
        '12345678901',
        'PENDING',
        CURRENT_TIMESTAMP -- Violates rule: PENDING must have NULL verified_at
    );
    RAISE EXCEPTION 'TEST 2.1 FAILED: PENDING KYC with verified_at timestamp was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 2.1: PENDING KYC with non-null verified_at rejected by chk_kyc_verification.';
END $$;

-- Test 2.2: Reject APPROVED KYC record without verified_at timestamp
DO $$
BEGIN
    INSERT INTO kyc_records (
        customer_id, tier_level, id_type, id_number, status, verified_at
    ) VALUES (
        '11111111-1111-1111-1111-111111111111',
        2,
        'BVN',
        '22334455667',
        'APPROVED',
        NULL -- Violates rule: APPROVED must have verified_at populated
    );
    RAISE EXCEPTION 'TEST 2.2 FAILED: APPROVED KYC without verified_at was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 2.2: APPROVED KYC with NULL verified_at rejected by chk_kyc_verification.';
END $$;

-- Test 2.3: Reject invalid KYC tier level (must be 1, 2, or 3)
DO $$
BEGIN
    INSERT INTO kyc_records (
        customer_id, tier_level, id_type, id_number, status, verified_at
    ) VALUES (
        '11111111-1111-1111-1111-111111111111',
        4, -- Invalid tier
        'PASSPORT',
        'A12345678',
        'PENDING',
        NULL
    );
    RAISE EXCEPTION 'TEST 2.3 FAILED: Invalid tier_level 4 was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 2.3: Invalid tier_level rejected by chk_kyc_tier.';
END $$;


-- ============================================================================
-- TEST SUITE 3: ACCOUNTS TABLE CONSTRAINTS
-- ============================================================================

-- Test 3.1: Reject account number not exactly 10 digits
DO $$
BEGIN
    INSERT INTO accounts (
        customer_id, account_number, account_name, balance, status
    ) VALUES (
        '11111111-1111-1111-1111-111111111111',
        '12345', -- Invalid: 5 digits instead of 10
        'Invalid Acc Length',
        1000.00,
        'ACTIVE'
    );
    RAISE EXCEPTION 'TEST 3.1 FAILED: Non-10-digit account number was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 3.1: Short account number rejected by chk_account_number_format.';
END $$;

-- Test 3.2: Reject alphanumeric characters in account number
DO $$
BEGIN
    INSERT INTO accounts (
        customer_id, account_number, account_name, balance, status
    ) VALUES (
        '11111111-1111-1111-1111-111111111111',
        '01234ABCDE', -- Invalid: contains letters
        'Alpha Account',
        1000.00,
        'ACTIVE'
    );
    RAISE EXCEPTION 'TEST 3.2 FAILED: Alphanumeric account number was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 3.2: Alphanumeric account number rejected by regex check.';
END $$;

-- Test 3.3: Reject negative wallet balance
DO $$
BEGIN
    INSERT INTO accounts (
        customer_id, account_number, account_name, balance, status
    ) VALUES (
        '11111111-1111-1111-1111-111111111111',
        '9876543210',
        'Negative Balance Wallet',
        -250.00, -- Invalid negative balance
        'ACTIVE'
    );
    RAISE EXCEPTION 'TEST 3.3 FAILED: Negative account balance was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 3.3: Negative balance rejected by chk_account_balance_positive.';
END $$;


-- ============================================================================
-- TEST SUITE 4: BENEFICIARIES TABLE CONSTRAINTS & CASCADING DELETION
-- ============================================================================

-- Test 4.1: Reject duplicate beneficiary under same customer and bank
DO $$
DECLARE
    v_temp_cust UUID;
BEGIN
    INSERT INTO customers (
        first_name, last_name, email, phone, customer_type
    ) VALUES (
        'Bene', 'Tester', 'bene.tester@quickfund.test', '+2348088887777', 'INDIVIDUAL'
    ) RETURNING customer_id INTO v_temp_cust;

    -- First insertion succeeds
    INSERT INTO beneficiaries (
        customer_id, beneficiary_account_number, bank_name, account_name
    ) VALUES (
        v_temp_cust, '1122334455', 'First Bank of Nigeria', 'Kemi Adeleke'
    );

    -- Duplicate insertion must fail
    INSERT INTO beneficiaries (
        customer_id, beneficiary_account_number, bank_name, account_name
    ) VALUES (
        v_temp_cust, '1122334455', 'First Bank of Nigeria', 'Kemi Adeleke Duplicate'
    );

    RAISE EXCEPTION 'TEST 4.1 FAILED: Duplicate beneficiary entry was permitted.';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE '[PASS] Test 4.1: Duplicate beneficiary entry rejected by uq_customer_beneficiary.';
END $$;

-- Test 4.2: Verify ON DELETE CASCADE on beneficiaries when customer is deleted
DO $$
DECLARE
    v_casc_cust UUID;
    v_bene_count INT;
BEGIN
    INSERT INTO customers (
        first_name, last_name, email, phone, customer_type
    ) VALUES (
        'Cascade', 'Customer', 'cascade.tester@quickfund.test', '+2348077776666', 'INDIVIDUAL'
    ) RETURNING customer_id INTO v_casc_cust;

    INSERT INTO beneficiaries (
        customer_id, beneficiary_account_number, bank_name, account_name
    ) VALUES (
        v_casc_cust, '9988776655', 'Zenith Bank', 'Tunde Bakare'
    );

    -- Delete customer
    DELETE FROM customers WHERE customer_id = v_casc_cust;

    -- Verify beneficiary was automatically removed
    SELECT COUNT(*) INTO v_bene_count
    FROM beneficiaries
    WHERE customer_id = v_casc_cust;

    IF v_bene_count != 0 THEN
        RAISE EXCEPTION 'TEST 4.2 FAILED: Beneficiary record was not cascaded upon customer deletion.';
    END IF;

    RAISE NOTICE '[PASS] Test 4.2: Beneficiary record cascaded successfully on customer deletion.';
END $$;


-- ============================================================================
-- TEST SUITE 5: CARDS TABLE CONSTRAINTS (PCI-DSS)
-- ============================================================================

-- Test 5.1: Reject last_four containing letters or invalid length
DO $$
BEGIN
    INSERT INTO cards (
        account_id, card_token, last_four, card_type, card_brand, expiry_month, expiry_year, cardholder_name
    ) VALUES (
        '22222222-2222-2222-2222-222222222222',
        'tok_card_test_invalid_last4',
        '432A', -- Invalid: contains 'A'
        'DEBIT',
        'MASTERCARD',
        12,
        2028,
        'Amara Okonkwo'
    );
    RAISE EXCEPTION 'TEST 5.1 FAILED: Non-numeric last_four digits were permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 5.1: Invalid card last_four format rejected by chk_card_last_four.';
END $$;

-- Test 5.2: Reject invalid card expiry month
DO $$
BEGIN
    INSERT INTO cards (
        account_id, card_token, last_four, card_type, card_brand, expiry_month, expiry_year, cardholder_name
    ) VALUES (
        '22222222-2222-2222-2222-222222222222',
        'tok_card_test_invalid_month',
        '1234',
        'VIRTUAL',
        'VISA',
        13, -- Invalid month
        2027,
        'Amara Okonkwo'
    );
    RAISE EXCEPTION 'TEST 5.2 FAILED: Invalid expiry month 13 was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 5.2: Out-of-range expiry month rejected by chk_card_expiry_month.';
END $$;


-- ============================================================================
-- TEST SUITE 6: TRANSACTIONS TABLE CONSTRAINTS & REVERSAL LOGIC
-- ============================================================================

-- Test 6.1: Reject transaction with non-positive amount (amount <= 0)
DO $$
BEGIN
    INSERT INTO transactions (
        idempotency_key, transaction_type, amount, currency, status
    ) VALUES (
        'IDEMP-ZERO-AMOUNT',
        'TRANSFER',
        0.00, -- Invalid non-positive amount
        'NGN',
        'PENDING'
    );
    RAISE EXCEPTION 'TEST 6.1 FAILED: Transaction with amount 0.00 was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 6.1: Zero transaction amount rejected by chk_tx_amount_positive.';
END $$;

-- Test 6.2: Reject duplicate idempotency key (duplicate processing prevention)
DO $$
BEGIN
    INSERT INTO transactions (
        idempotency_key, transaction_type, amount, currency, status
    ) VALUES (
        'IDEMP-TEST-BASE-001', -- Existing key from baseline
        'TRANSFER',
        1000.00,
        'NGN',
        'PENDING'
    );
    RAISE EXCEPTION 'TEST 6.2 FAILED: Duplicate idempotency key was permitted.';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE '[PASS] Test 6.2: Duplicate idempotency key rejected (UNIQUE violation).';
END $$;

-- Test 6.3: Reject REVERSAL transaction that lacks a reversal_of reference
DO $$
BEGIN
    INSERT INTO transactions (
        idempotency_key, transaction_type, amount, currency, reversal_of, status
    ) VALUES (
        'IDEMP-REV-NO-PARENT',
        'REVERSAL',
        5000.00,
        'NGN',
        NULL, -- Violates rule: REVERSAL must reference original transaction
        'PENDING'
    );
    RAISE EXCEPTION 'TEST 6.3 FAILED: REVERSAL without reversal_of reference was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 6.3: REVERSAL with NULL reversal_of rejected by chk_tx_reversal_logic.';
END $$;

-- Test 6.4: Reject NON-REVERSAL transaction referencing a reversal_of
DO $$
BEGIN
    INSERT INTO transactions (
        idempotency_key, transaction_type, amount, currency, reversal_of, status
    ) VALUES (
        'IDEMP-NON-REV-WITH-PARENT',
        'TRANSFER', -- Not a reversal
        5000.00,
        'NGN',
        '33333333-3333-3333-3333-333333333333', -- Violates rule: non-reversal must not have reversal_of
        'PENDING'
    );
    RAISE EXCEPTION 'TEST 6.4 FAILED: TRANSFER with non-null reversal_of was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 6.4: Non-reversal with populated reversal_of rejected by chk_tx_reversal_logic.';
END $$;


-- ============================================================================
-- TEST SUITE 7: LEDGER ENTRIES CONSTRAINTS
-- ============================================================================

-- Test 7.1: Reject duplicate entry direction for the same account in one transaction
DO $$
BEGIN
    -- First debit entry for the account
    INSERT INTO ledger_entries (
        transaction_id, account_id, entry_direction, amount
    ) VALUES (
        '33333333-3333-3333-3333-333333333333',
        '22222222-2222-2222-2222-222222222222',
        'DEBIT',
        25000.00
    );

    -- Duplicate debit entry for the SAME account in the SAME transaction must fail
    INSERT INTO ledger_entries (
        transaction_id, account_id, entry_direction, amount
    ) VALUES (
        '33333333-3333-3333-3333-333333333333',
        '22222222-2222-2222-2222-222222222222',
        'DEBIT',
        10000.00
    );
    RAISE EXCEPTION 'TEST 7.1 FAILED: Duplicate account direction in transaction was permitted.';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE '[PASS] Test 7.1: Duplicate account direction in transaction rejected by uq_tx_account_direction.';
END $$;

-- Test 7.2: Reject invalid ledger entry direction (must be DEBIT or CREDIT)
DO $$
BEGIN
    INSERT INTO ledger_entries (
        transaction_id, account_id, entry_direction, amount
    ) VALUES (
        '33333333-3333-3333-3333-333333333333',
        '22222222-2222-2222-2222-222222222222',
        'HOLD', -- Invalid direction
        5000.00
    );
    RAISE EXCEPTION 'TEST 7.2 FAILED: Invalid ledger direction HOLD was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 7.2: Invalid ledger direction rejected by chk_ledger_direction.';
END $$;


-- ============================================================================
-- TEST SUITE 8: FRAUD FLAGS TABLE CONSTRAINTS
-- ============================================================================

-- Test 8.1: Reject out-of-range risk score (> 100)
DO $$
BEGIN
    INSERT INTO fraud_flags (
        transaction_id, risk_score, risk_level, reason, status
    ) VALUES (
        '33333333-3333-3333-3333-333333333333',
        105, -- Invalid score > 100
        'CRITICAL',
        'High-velocity transaction pattern',
        'OPEN'
    );
    RAISE EXCEPTION 'TEST 8.1 FAILED: Risk score 105 was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 8.1: Risk score > 100 rejected by chk_fraud_risk_score.';
END $$;

-- Test 8.2: Reject invalid risk level string
DO $$
BEGIN
    INSERT INTO fraud_flags (
        transaction_id, risk_score, risk_level, reason, status
    ) VALUES (
        '33333333-3333-3333-3333-333333333333',
        75,
        'SEVERE', -- Invalid level (allowed: LOW, MEDIUM, HIGH, CRITICAL)
        'IP geolocation anomaly',
        'OPEN'
    );
    RAISE EXCEPTION 'TEST 8.2 FAILED: Invalid risk level SEVERE was permitted.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[PASS] Test 8.2: Invalid risk_level rejected by chk_fraud_risk_level.';
END $$;


-- ============================================================================
-- TEST SUITE 9: IMMUTABILITY & RESTRICT CONSTRAINTS
-- ============================================================================

-- Test 9.1: Reject deletion of an account that has ledger entries (ON DELETE RESTRICT)
DO $$
BEGIN
    DELETE FROM accounts WHERE account_id = '22222222-2222-2222-2222-222222222222';
    RAISE EXCEPTION 'TEST 9.1 FAILED: Account with ledger history was deleted.';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE '[PASS] Test 9.1: Account deletion blocked by foreign key RESTRICT (ledger history preserved).';
END $$;

-- Test 9.2: Reject deletion of a transaction that has ledger entries (ON DELETE RESTRICT)
DO $$
BEGIN
    DELETE FROM transactions WHERE transaction_id = '33333333-3333-3333-3333-333333333333';
    RAISE EXCEPTION 'TEST 9.2 FAILED: Transaction with ledger history was deleted.';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE '[PASS] Test 9.2: Transaction deletion blocked by foreign key RESTRICT (audit trail preserved).';
END $$;


-- ============================================================================
-- SUMMARY OF TEST EXECUTION
-- ============================================================================
SELECT '=====================================================' AS test_result;
SELECT 'ALL 16 CONSTRAINT & INTEGRITY TESTS PASSED SUCCESSFULLY' AS test_result;
SELECT '=====================================================' AS test_result;
