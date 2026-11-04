-- =====================================================================
-- Portfolio 3, own experiment: safe reversal of a completed transfer.
-- reverse_transfer() undoes a SUCCESS transfer as a NEW REVERSAL
-- transaction (the ledger is append-only, so nothing is deleted), and
-- marks the original REVERSED. It is idempotent, locks in a fixed order,
-- and refuses to reverse the same transfer twice.
-- =====================================================================
CREATE OR REPLACE FUNCTION reverse_transfer(
    p_original_id UUID,
    p_key         VARCHAR,
    p_description VARCHAR DEFAULT 'Reversal'
) RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_orig      transactions%ROWTYPE;
    v_debit_id  UUID;   -- account the original took money from
    v_credit_id UUID;   -- account the original paid money to
    v_rev_id    UUID;
    v_bal       NUMERIC;
BEGIN
    -- 0. Idempotency: a retried reversal returns the same id.
    SELECT transaction_id INTO v_rev_id FROM transactions WHERE idempotency_key = p_key;
    IF v_rev_id IS NOT NULL THEN
        RETURN v_rev_id;
    END IF;

    -- 1. Lock the original transaction row, so two reversals cannot run at once.
    SELECT * INTO v_orig FROM transactions WHERE transaction_id = p_original_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'TRANSACTION_NOT_FOUND';
    END IF;
    IF v_orig.transaction_type <> 'TRANSFER' OR v_orig.status <> 'SUCCESS' THEN
        RAISE EXCEPTION 'NOT_REVERSIBLE: only a SUCCESS transfer can be reversed (status is %)', v_orig.status;
    END IF;

    -- 2. Find the two accounts from the original ledger lines.
    SELECT account_id INTO v_debit_id  FROM ledger_entries
     WHERE transaction_id = p_original_id AND entry_direction = 'DEBIT';
    SELECT account_id INTO v_credit_id FROM ledger_entries
     WHERE transaction_id = p_original_id AND entry_direction = 'CREDIT';

    -- 3. Lock both accounts in a fixed order (lowest account_id first).
    PERFORM 1 FROM accounts WHERE account_id = LEAST(v_debit_id, v_credit_id)    FOR UPDATE;
    PERFORM 1 FROM accounts WHERE account_id = GREATEST(v_debit_id, v_credit_id) FOR UPDATE;

    -- 4. The receiver must be able to give the money back.
    SELECT balance INTO v_bal FROM accounts WHERE account_id = v_credit_id;
    IF v_bal < v_orig.amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_FUNDS: receiver balance % is less than %', v_bal, v_orig.amount;
    END IF;

    -- 5. Register the reversal, move the money back, post the mirror ledger lines.
    INSERT INTO transactions (idempotency_key, transaction_type, status, amount, currency, reversal_of, description)
    VALUES (p_key, 'REVERSAL', 'PENDING', v_orig.amount, v_orig.currency, p_original_id, p_description)
    RETURNING transaction_id INTO v_rev_id;

    UPDATE accounts SET balance = balance - v_orig.amount WHERE account_id = v_credit_id;
    UPDATE accounts SET balance = balance + v_orig.amount WHERE account_id = v_debit_id;

    INSERT INTO ledger_entries (transaction_id, account_id, entry_direction, amount, created_at)
    VALUES (v_rev_id, v_credit_id, 'DEBIT',  v_orig.amount, clock_timestamp()),
           (v_rev_id, v_debit_id,  'CREDIT', v_orig.amount, clock_timestamp());

    UPDATE transactions SET status = 'SUCCESS', completed_at = clock_timestamp()
     WHERE transaction_id = v_rev_id;
    UPDATE transactions SET status = 'REVERSED' WHERE transaction_id = p_original_id;

    RETURN v_rev_id;
END;
$$;