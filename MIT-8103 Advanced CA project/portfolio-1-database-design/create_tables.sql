-- ============================================================================
-- Course: MIT-8103: Advanced Database Systems
-- Project: Continuous Assessment - Portfolio 1 (Database Design)
-- Script: create_tables.sql
-- Description: DDL script creating all 8 core tables for the QuickFund platform.
--              Implements all domain constraints, business rules, foreign keys,
--              and data integrity checks.
-- ============================================================================

-- Ensure cryptographic extension for UUID generation if needed
BEGIN; 
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Clean teardown (in reverse dependency order) for idempotency
DROP TABLE IF EXISTS fraud_flags CASCADE;
DROP TABLE IF EXISTS ledger_entries CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS cards CASCADE;
DROP TABLE IF EXISTS beneficiaries CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;
DROP TABLE IF EXISTS kyc_records CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- ============================================================================
-- 1. CUSTOMERS TABLE
-- Description: Core profile entity for individuals and registered merchants.
-- Business Rules:
--   - Email and phone must be unique across all customers.
--   - Type must be strictly 'INDIVIDUAL' or 'MERCHANT'.
-- ============================================================================
CREATE TABLE customers (
    customer_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE,
    phone           VARCHAR(20) NOT NULL UNIQUE,
    customer_type   VARCHAR(20) NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_customer_type CHECK (customer_type IN ('INDIVIDUAL', 'MERCHANT'))
);

-- ============================================================================
-- 2. KYC_RECORDS TABLE
-- Description: Stores customer identity verification submissions and tiers.
-- Business Rules:
--   - A customer can submit multiple KYC records over time.
--   - Verified timestamp can only be populated if status != 'PENDING'.
-- ============================================================================
CREATE TABLE kyc_records (
    kyc_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    tier_level      INT NOT NULL,
    id_type         VARCHAR(50) NOT NULL,
    id_number       VARCHAR(100) NOT NULL,
    document_url    VARCHAR(500),
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    rejection_reason TEXT,
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    verified_at     TIMESTAMPTZ,

    CONSTRAINT chk_kyc_tier CHECK (tier_level IN (1, 2, 3)),
    CONSTRAINT chk_kyc_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    CONSTRAINT chk_kyc_verification CHECK (
        (status = 'PENDING' AND verified_at IS NULL) OR
        (status IN ('APPROVED', 'REJECTED') AND verified_at IS NOT NULL)
    )
);

-- ============================================================================
-- 3. ACCOUNTS TABLE
-- Description: Customer wallet accounts holding monetary balances.
-- Business Rules:
--   - Account number must be unique and exactly 10 numeric digits (NUBAN format).
--   - Balance must be non-negative and use exact decimal precision.
--   - Financial accounts must not be hard deleted if transactions exist.
-- ============================================================================
CREATE TABLE accounts (
    account_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    account_number  VARCHAR(10) NOT NULL UNIQUE,
    account_name    VARCHAR(200) NOT NULL,
    balance         NUMERIC(15, 2) NOT NULL DEFAULT 0.00,
    currency        VARCHAR(3) NOT NULL DEFAULT 'NGN',
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_account_number_format CHECK (account_number ~ '^[0-9]{10}$'),
    CONSTRAINT chk_account_balance_positive CHECK (balance >= 0.00),
    CONSTRAINT chk_account_status CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED'))
);

-- ============================================================================
-- 4. BENEFICIARIES TABLE
-- Description: Saved recipient bank/wallet details for repeat transfers.
-- Business Rules:
--   - Beneficiaries must be removed when the parent customer is deleted (CASCADE).
--   - Account number must be exactly 10 digits.
--   - A customer cannot save duplicate recipient accounts under the same bank.
-- ============================================================================
CREATE TABLE beneficiaries (
    beneficiary_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id                 UUID NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    beneficiary_account_number  VARCHAR(10) NOT NULL,
    bank_name                   VARCHAR(100) NOT NULL,
    account_name                VARCHAR(200) NOT NULL,
    nickname                    VARCHAR(100),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_beneficiary_acc_num CHECK (beneficiary_account_number ~ '^[0-9]{10}$'),
    CONSTRAINT uq_customer_beneficiary UNIQUE (customer_id, beneficiary_account_number, bank_name)
);

-- ============================================================================
-- 5. CARDS TABLE
-- Description: Debit and virtual cards linked to wallet accounts.
-- Business Rules:
--   - PCI-DSS Compliance: Only the last 4 digits are stored; full PAN is never stored.
--   - Must link to an active account.
-- ============================================================================
CREATE TABLE cards (
    card_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    card_token      VARCHAR(255) NOT NULL UNIQUE,
    last_four       VARCHAR(4) NOT NULL,
    card_type       VARCHAR(20) NOT NULL,
    card_brand      VARCHAR(20) NOT NULL,
    expiry_month    INT NOT NULL,
    expiry_year     INT NOT NULL,
    cardholder_name VARCHAR(150) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_card_last_four CHECK (last_four ~ '^[0-9]{4}$'),
    CONSTRAINT chk_card_type CHECK (card_type IN ('DEBIT', 'VIRTUAL')),
    CONSTRAINT chk_card_brand CHECK (card_brand IN ('VERVE', 'MASTERCARD', 'VISA')),
    CONSTRAINT chk_card_expiry_month CHECK (expiry_month BETWEEN 1 AND 12),
    CONSTRAINT chk_card_expiry_year CHECK (expiry_year >= 2024),
    CONSTRAINT chk_card_status CHECK (status IN ('ACTIVE', 'BLOCKED', 'EXPIRED'))
);

-- ============================================================================
-- 6. TRANSACTIONS TABLE
-- Description: Top-level event log of all financial interactions.
-- Business Rules:
--   - Amount must be strictly greater than 0 with exact decimal precision.
--   - Idempotency key must be unique to prevent double-charging.
--   - A REVERSAL transaction must reference the original transaction (reversal_of).
--   - Non-reversal transactions must NOT reference another transaction.
--   - Financial transactions must be preserved (ON DELETE RESTRICT).
-- ============================================================================
CREATE TABLE transactions (
    transaction_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key     VARCHAR(100) NOT NULL UNIQUE,
    transaction_type    VARCHAR(20) NOT NULL,
    amount              NUMERIC(15, 2) NOT NULL,
    currency            VARCHAR(3) NOT NULL DEFAULT 'NGN',
    reversal_of         UUID REFERENCES transactions(transaction_id) ON DELETE RESTRICT,
    status              VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    description         VARCHAR(255),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at        TIMESTAMPTZ,

    CONSTRAINT chk_tx_amount_positive CHECK (amount > 0.00),
    CONSTRAINT chk_tx_type CHECK (transaction_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'BILL_PAYMENT', 'REVERSAL')),
    CONSTRAINT chk_tx_status CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED', 'REVERSED')),
    CONSTRAINT chk_tx_reversal_logic CHECK (
        (transaction_type = 'REVERSAL' AND reversal_of IS NOT NULL) OR
        (transaction_type != 'REVERSAL' AND reversal_of IS NULL)
    )
);

-- ============================================================================
-- 7. LEDGER_ENTRIES TABLE
-- Description: Immutable double-entry bookkeeping records (debits and credits).
-- Business Rules:
--   - Connects accounts and transactions.
--   - Amount must be strictly positive.
--   - An account cannot appear more than once in the same direction
--     (DEBIT or CREDIT) within a single transaction.
--   - All records are immutable; no hard deletion (ON DELETE RESTRICT).
-- ============================================================================
CREATE TABLE ledger_entries (
    entry_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id  UUID NOT NULL REFERENCES transactions(transaction_id) ON DELETE RESTRICT,
    account_id      UUID NOT NULL REFERENCES accounts(account_id) ON DELETE RESTRICT,
    entry_direction VARCHAR(10) NOT NULL,
    amount          NUMERIC(15, 2) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_ledger_direction CHECK (entry_direction IN ('DEBIT', 'CREDIT')),
    CONSTRAINT chk_ledger_amount_positive CHECK (amount > 0.00),
    CONSTRAINT uq_tx_account_direction UNIQUE (transaction_id, account_id, entry_direction)
);

-- ============================================================================
-- 8. FRAUD_FLAGS TABLE
-- Description: Automated compliance and suspicious activity tracking.
-- Business Rules:
--   - Belongs to a specific transaction.
--   - Risk score must be an integer between 0 and 100.
--   - Captures status of compliance investigations.
-- ============================================================================
CREATE TABLE fraud_flags (
    flag_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id  UUID NOT NULL REFERENCES transactions(transaction_id) ON DELETE CASCADE,
    risk_score      INT NOT NULL,
    risk_level      VARCHAR(20) NOT NULL,
    reason          TEXT NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    flagged_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at     TIMESTAMPTZ,

    CONSTRAINT chk_fraud_risk_score CHECK (risk_score BETWEEN 0 AND 100),
    CONSTRAINT chk_fraud_risk_level CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    CONSTRAINT chk_fraud_flag_status CHECK (status IN ('OPEN', 'INVESTIGATING', 'CLEARED', 'CONFIRMED_FRAUD'))
);

-- ============================================================================
-- PERFORMANCE & INTEGRITY INDEXES
-- ============================================================================
CREATE INDEX idx_kyc_customer_id ON kyc_records(customer_id);
CREATE INDEX idx_accounts_customer_id ON accounts(customer_id);
CREATE INDEX idx_beneficiaries_customer_id ON beneficiaries(customer_id);
CREATE INDEX idx_cards_account_id ON cards(account_id);
CREATE INDEX idx_transactions_type_status ON transactions(transaction_type, status);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_ledger_entries_tx ON ledger_entries(transaction_id);
CREATE INDEX idx_ledger_entries_account ON ledger_entries(account_id);
CREATE INDEX idx_fraud_flags_tx ON fraud_flags(transaction_id);

COMMIT;