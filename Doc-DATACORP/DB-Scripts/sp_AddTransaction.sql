-- ============================================
-- STORED PROCEDURE: sp_AddTransaction
-- Adds a financial transaction with full validation
-- ============================================

CREATE OR REPLACE PROCEDURE sp_addtransaction(
    -- Input parameters
    p_contract_id INTEGER,
    p_transaction_type VARCHAR(30),
    p_amount DECIMAL(15,2),
    p_agency_id INTEGER,
    p_performed_by INTEGER,
    p_description TEXT DEFAULT NULL,
    p_currency VARCHAR(3) DEFAULT 'XAF',
    p_verified_by INTEGER DEFAULT NULL,
    
    -- Output parameters
    OUT p_transaction_id BIGINT,
    OUT p_transaction_ref VARCHAR(50),
    OUT p_status_message VARCHAR(200)
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_contract_exists BOOLEAN;
    v_contract_status VARCHAR(20);
    v_contract_agency_id INTEGER;
    v_agency_exists BOOLEAN;
    v_user_exists BOOLEAN;
    v_verifier_exists BOOLEAN;
    v_balance_check DECIMAL(15,2);
    v_sequence_number INTEGER;
BEGIN
    -- Initialize outputs
    p_transaction_id := 0;
    p_transaction_ref := '';
    p_status_message := '';
    
    -- 1. BASIC VALIDATIONS
    IF p_contract_id IS NULL THEN
        p_status_message := 'Contract ID is required';
        RETURN;
    END IF;
    
    IF p_transaction_type IS NULL THEN
        p_status_message := 'Transaction type is required';
        RETURN;
    END IF;
    
    IF p_amount IS NULL OR p_amount = 0 THEN
        p_status_message := 'Transaction amount cannot be zero';
        RETURN;
    END IF;
    
    IF p_agency_id IS NULL THEN
        p_status_message := 'Agency ID is required';
        RETURN;
    END IF;
    
    IF p_performed_by IS NULL THEN
        p_status_message := 'Performed by user is required';
        RETURN;
    END IF;
    
    -- 2. VALIDATE CONTRACT
    SELECT 
        EXISTS (SELECT 1 FROM contracts WHERE contract_id = p_contract_id),
        status,
        agency_id
    INTO 
        v_contract_exists,
        v_contract_status,
        v_contract_agency_id
    FROM contracts 
    WHERE contract_id = p_contract_id;
    
    IF NOT v_contract_exists THEN
        p_status_message := 'Contract ID ' || p_contract_id || ' does not exist';
        RETURN;
    END IF;
    
    -- Check if contract is active
    IF v_contract_status NOT IN ('ACTIVE', 'DRAFT') THEN
        p_status_message := 'Contract is not active. Current status: ' || v_contract_status;
        RETURN;
    END IF;
    
    -- Verify contract belongs to specified agency
    IF v_contract_agency_id != p_agency_id THEN
        p_status_message := 'Contract belongs to agency ID ' || v_contract_agency_id || 
                           ', not agency ID ' || p_agency_id;
        RETURN;
    END IF;
    
    -- 3. VALIDATE AGENCY
    SELECT EXISTS (
        SELECT 1 FROM agencies 
        WHERE agency_id = p_agency_id 
        AND is_active = TRUE
    ) INTO v_agency_exists;
    
    IF NOT v_agency_exists THEN
        p_status_message := 'Agency ID ' || p_agency_id || ' does not exist or is inactive';
        RETURN;
    END IF;
    
    -- 4. VALIDATE USERS
    -- Check performer
    SELECT EXISTS (
        SELECT 1 FROM users 
        WHERE user_id = p_performed_by 
        AND is_active = TRUE
    ) INTO v_user_exists;
    
    IF NOT v_user_exists THEN
        p_status_message := 'Performing user ID ' || p_performed_by || ' does not exist or is inactive';
        RETURN;
    END IF;
    
    -- Check verifier (if provided)
    IF p_verified_by IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM users 
            WHERE user_id = p_verified_by 
            AND is_active = TRUE
        ) INTO v_verifier_exists;
        
        IF NOT v_verifier_exists THEN
            p_status_message := 'Verifying user ID ' || p_verified_by || ' does not exist or is inactive';
            RETURN;
        END IF;
    END IF;
    
    -- 5. VALIDATE TRANSACTION TYPE
    IF p_transaction_type NOT IN ('PAYMENT', 'DEPOSIT', 'WITHDRAWAL', 'FEE', 'INTEREST', 'REFUND', 'ADJUSTMENT', 'PENALTY') THEN
        p_status_message := 'Invalid transaction type: ' || p_transaction_type;
        RETURN;
    END IF;
    
    -- 6. VALIDATE CURRENCY
    IF p_currency NOT IN ('XAF', 'EUR', 'USD') THEN
        p_status_message := 'Unsupported currency: ' || p_currency;
        RETURN;
    END IF;
    
    -- 7. GENERATE TRANSACTION REFERENCE
    SELECT COALESCE(MAX(transaction_id), 0) + 1 INTO v_sequence_number 
    FROM transactions;
    
    p_transaction_ref := 'TXN-' || 
                        TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || 
                        LPAD(v_sequence_number::TEXT, 6, '0');
    
    -- 8. VALIDATE FOR WITHDRAWALS (check balance)
    IF p_transaction_type = 'WITHDRAWAL' THEN
        -- Calculate current balance for this contract
        SELECT COALESCE(SUM(
            CASE 
                WHEN transaction_type IN ('DEPOSIT', 'PAYMENT') THEN amount
                WHEN transaction_type IN ('WITHDRAWAL', 'FEE') THEN -amount
                ELSE 0
            END
        ), 0) INTO v_balance_check
        FROM transactions
        WHERE contract_id = p_contract_id 
        AND status = 'COMPLETED';
        
        IF v_balance_check < p_amount THEN
            p_status_message := 'Insufficient balance. Available: ' || v_balance_check || ', Requested: ' || p_amount;
            RETURN;
        END IF;
    END IF;
    
    -- 9. INSERT TRANSACTION
    INSERT INTO transactions (
        transaction_ref,
        contract_id,
        transaction_type,
        amount,
        currency,
        description,
        agency_id,
        performed_by,
        verified_by,
        transaction_date,
        status,
        notes,
        created_at
    ) VALUES (
        p_transaction_ref,
        p_contract_id,
        p_transaction_type,
        p_amount,
        p_currency,
        p_description,
        p_agency_id,
        p_performed_by,
        p_verified_by,
        CURRENT_TIMESTAMP,
        'COMPLETED',
        CASE 
            WHEN p_verified_by IS NOT NULL THEN 'Verified transaction'
            ELSE 'Pending verification'
        END,
        CURRENT_TIMESTAMP
    ) RETURNING transaction_id INTO p_transaction_id;
    
    -- 10. UPDATE CONTRACT STATUS IF NEEDED
    IF p_transaction_type = 'PAYMENT' AND v_contract_status = 'DRAFT' THEN
        UPDATE contracts 
        SET status = 'ACTIVE',
            updated_at = CURRENT_TIMESTAMP
        WHERE contract_id = p_contract_id;
        
        RAISE NOTICE 'Contract % activated after first payment', p_contract_id;
    END IF;
    
    -- 11. SET SUCCESS MESSAGE
    p_status_message := 'Transaction added successfully. Reference: ' || p_transaction_ref;
    
    RAISE NOTICE 'Transaction % created for contract %, amount: %', 
        p_transaction_ref, p_contract_id, p_amount;
    
EXCEPTION
    WHEN OTHERS THEN
        p_status_message := 'Error adding transaction: ' || SQLERRM;
        p_transaction_id := 0;
        p_transaction_ref := '';
        RAISE NOTICE 'Error in sp_addtransaction: %', SQLERRM;
END;
$$;

-- ============================================
-- VERSION 2: Simple Transaction (Minimal validation)
-- ============================================

CREATE OR REPLACE PROCEDURE sp_addtransaction_simple(
    p_contract_id INTEGER,
    p_transaction_type VARCHAR(30),
    p_amount DECIMAL(15,2),
    p_agency_id INTEGER,
    p_performed_by INTEGER,
    OUT p_transaction_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction_ref VARCHAR(50);
BEGIN
    -- Generate reference
    SELECT 'TXN-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || 
           LPAD((COALESCE((SELECT MAX(transaction_id) FROM transactions), 0) + 1)::TEXT, 5, '0')
    INTO v_transaction_ref;
    
    -- Insert transaction
    INSERT INTO transactions (
        transaction_ref,
        contract_id,
        transaction_type,
        amount,
        agency_id,
        performed_by,
        status
    ) VALUES (
        v_transaction_ref,
        p_contract_id,
        p_transaction_type,
        p_amount,
        p_agency_id,
        p_performed_by,
        'COMPLETED'
    ) RETURNING transaction_id INTO p_transaction_id;
END;
$$;

-- ============================================
-- VERSION 3: Transaction with Receipt Generation
-- ============================================

CREATE OR REPLACE PROCEDURE sp_addtransaction_withreceipt(
    p_contract_id INTEGER,
    p_transaction_type VARCHAR(30),
    p_amount DECIMAL(15,2),
    p_agency_id INTEGER,
    p_performed_by INTEGER,
    p_description TEXT DEFAULT NULL,
    OUT p_transaction_id BIGINT,
    OUT p_receipt_number VARCHAR(50),
    OUT p_receipt_details JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_client_id INTEGER;
    v_client_name VARCHAR(100);
    v_contract_number VARCHAR(30);
    v_agency_name VARCHAR(100);
    v_city VARCHAR(50);
    v_balance_after DECIMAL(15,2);
BEGIN
    -- Get client and contract info
    SELECT 
        c.client_id,
        c.full_name,
        ct.contract_number,
        a.agency_name,
        a.city
    INTO 
        v_client_id,
        v_client_name,
        v_contract_number,
        v_agency_name,
        v_city
    FROM contracts ct
    JOIN clients c ON ct.client_id = c.client_id
    JOIN agencies a ON ct.agency_id = a.agency_id
    WHERE ct.contract_id = p_contract_id;
    
    -- Generate receipt number
    p_receipt_number := 'RC-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || 
                       LPAD((COALESCE((SELECT MAX(transaction_id) FROM transactions), 0) + 1)::TEXT, 6, '0');
    
    -- Calculate new balance
    SELECT COALESCE(SUM(
        CASE 
            WHEN transaction_type IN ('DEPOSIT', 'PAYMENT') THEN amount
            WHEN transaction_type IN ('WITHDRAWAL', 'FEE') THEN -amount
            ELSE 0
        END
    ), 0) + 
    CASE 
        WHEN p_transaction_type IN ('DEPOSIT', 'PAYMENT') THEN p_amount
        WHEN p_transaction_type IN ('WITHDRAWAL', 'FEE') THEN -p_amount
        ELSE 0
    END
    INTO v_balance_after
    FROM transactions
    WHERE contract_id = p_contract_id 
    AND status = 'COMPLETED';
    
    -- Call main transaction procedure
    CALL sp_addtransaction(
        p_contract_id,
        p_transaction_type,
        p_amount,
        p_agency_id,
        p_performed_by,
        p_description,
        'XAF',
        NULL,
        p_transaction_id,
        p_receipt_number, -- Using receipt as transaction ref
        p_receipt_details::VARCHAR
    );
    
    -- Create receipt details
    p_receipt_details := jsonb_build_object(
        'receipt_number', p_receipt_number,
        'date', CURRENT_DATE,
        'time', CURRENT_TIME,
        'client_id', v_client_id,
        'client_name', v_client_name,
        'contract_number', v_contract_number,
        'transaction_type', p_transaction_type,
        'amount', p_amount,
        'currency', 'XAF',
        'agency', v_agency_name,
        'city', v_city,
        'performed_by', p_performed_by,
        'description', p_description,
        'balance_before', v_balance_after - 
            CASE 
                WHEN p_transaction_type IN ('DEPOSIT', 'PAYMENT') THEN p_amount
                WHEN p_transaction_type IN ('WITHDRAWAL', 'FEE') THEN -p_amount
                ELSE 0
            END,
        'balance_after', v_balance_after
    );
    
END;
$$;

-- ============================================
-- VERSION 4: Batch Transaction Processing
-- ============================================

CREATE OR REPLACE PROCEDURE sp_addtransaction_batch(
    p_transactions JSONB,
    p_agency_id INTEGER,
    p_performed_by INTEGER,
    OUT p_success_count INTEGER,
    OUT p_failed_count INTEGER,
    OUT p_results JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction RECORD;
    v_transaction_id BIGINT;
    v_transaction_ref VARCHAR(50);
    v_status_message VARCHAR(200);
    v_result JSONB;
    v_results_array JSONB := '[]'::JSONB;
BEGIN
    p_success_count := 0;
    p_failed_count := 0;
    
    -- Process each transaction in the batch
    FOR v_transaction IN 
        SELECT * FROM jsonb_to_recordset(p_transactions) AS x(
            contract_id INTEGER,
            transaction_type VARCHAR(30),
            amount DECIMAL(15,2),
            description TEXT
        )
    LOOP
        BEGIN
            -- Call main transaction procedure for each
            CALL sp_addtransaction(
                v_transaction.contract_id,
                v_transaction.transaction_type,
                v_transaction.amount,
                p_agency_id,
                p_performed_by,
                v_transaction.description,
                'XAF',
                NULL,
                v_transaction_id,
                v_transaction_ref,
                v_status_message
            );
            
            v_result := jsonb_build_object(
                'contract_id', v_transaction.contract_id,
                'transaction_id', v_transaction_id,
                'transaction_ref', v_transaction_ref,
                'status', 'SUCCESS',
                'message', v_status_message
            );
            
            p_success_count := p_success_count + 1;
            
        EXCEPTION WHEN OTHERS THEN
            v_result := jsonb_build_object(
                'contract_id', v_transaction.contract_id,
                'status', 'FAILED',
                'message', SQLERRM
            );
            
            p_failed_count := p_failed_count + 1;
        END;
        
        -- Add to results array
        v_results_array := v_results_array || v_result;
    END LOOP;
    
    p_results := jsonb_build_object(
        'total_processed', p_success_count + p_failed_count,
        'successful', p_success_count,
        'failed', p_failed_count,
        'transactions', v_results_array,
        'processed_at', CURRENT_TIMESTAMP
    );
    
END;
$$;

-- ============================================
-- GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON PROCEDURE sp_addtransaction TO agency_manager, agency_staff;
GRANT EXECUTE ON PROCEDURE sp_addtransaction_simple TO agency_staff;
GRANT EXECUTE ON PROCEDURE sp_addtransaction_withreceipt TO agency_manager;
GRANT EXECUTE ON PROCEDURE sp_addtransaction_batch TO agency_manager;

-- ============================================
-- USAGE EXAMPLES
-- ============================================

/*
-- Example 1: Basic transaction
DO $$
DECLARE
    v_transaction_id BIGINT;
    v_transaction_ref VARCHAR(50);
    v_message VARCHAR(200);
BEGIN
    CALL sp_addtransaction(
        1,                          -- contract_id
        'PAYMENT',                  -- transaction_type
        50000.00,                   -- amount
        2,                          -- agency_id (Douala)
        3,                          -- performed_by (user_id)
        'Monthly payment for loan', -- description
        'XAF',                      -- currency
        NULL,                       -- verified_by (optional)
        v_transaction_id,           -- OUTPUT
        v_transaction_ref,          -- OUTPUT
        v_message                   -- OUTPUT
    );
    
    RAISE NOTICE 'Transaction ID: %, Reference: %, Message: %', 
        v_transaction_id, v_transaction_ref, v_message;
END $$;

-- Example 2: With receipt
DO $$
DECLARE
    v_transaction_id BIGINT;
    v_receipt_number VARCHAR(50);
    v_receipt_details JSONB;
BEGIN
    CALL sp_addtransaction_withreceipt(
        1,                          -- contract_id
        'PAYMENT',                  -- transaction_type
        50000.00,                   -- amount
        2,                          -- agency_id
        3,                          -- performed_by
        'Monthly installment',      -- description
        v_transaction_id,           -- OUTPUT
        v_receipt_number,           -- OUTPUT
        v_receipt_details           -- OUTPUT
    );
    
    RAISE NOTICE 'Receipt: %, Details: %', v_receipt_number, v_receipt_details;
END $$;

-- Example 3: Batch processing
DO $$
DECLARE
    v_success_count INTEGER;
    v_failed_count INTEGER;
    v_results JSONB;
    v_transactions JSONB := '[
        {"contract_id": 1, "transaction_type": "PAYMENT", "amount": 25000, "description": "Payment 1"},
        {"contract_id": 2, "transaction_type": "DEPOSIT", "amount": 100000, "description": "Initial deposit"},
        {"contract_id": 3, "transaction_type": "FEE", "amount": 5000, "description": "Service fee"}
    ]';
BEGIN
    CALL sp_addtransaction_batch(
        v_transactions,             -- transactions array
        2,                          -- agency_id
        3,                          -- performed_by
        v_success_count,            -- OUTPUT
        v_failed_count,             -- OUTPUT
        v_results                   -- OUTPUT
    );
    
    RAISE NOTICE 'Batch results: %', v_results;
END $$;
*/

-- ============================================
-- TESTING UTILITY FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION test_transaction_procedure()
RETURNS TABLE(
    test_name VARCHAR(100),
    result VARCHAR(20),
    message TEXT
) 
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction_id BIGINT;
    v_transaction_ref VARCHAR(50);
    v_message VARCHAR(200);
BEGIN
    -- Test 1: Valid transaction
    BEGIN
        CALL sp_addtransaction(
            1, 'PAYMENT', 10000, 2, 3, 'Test payment',
            'XAF', NULL, v_transaction_id, v_transaction_ref, v_message
        );
        
        RETURN QUERY SELECT 
            'Valid transaction'::VARCHAR,
            'PASS'::VARCHAR,
            'Transaction created: ' || v_transaction_ref;
            
        -- Cleanup
        DELETE FROM transactions WHERE transaction_id = v_transaction_id;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 
            'Valid transaction'::VARCHAR,
            'FAIL'::VARCHAR,
            SQLERRM;
    END;
    
    -- Test 2: Invalid contract
    BEGIN
        CALL sp_addtransaction(
            9999, 'PAYMENT', 10000, 2, 3, 'Test',
            'XAF', NULL, v_transaction_id, v_transaction_ref, v_message
        );
        
        RETURN QUERY SELECT 
            'Invalid contract'::VARCHAR,
            'FAIL'::VARCHAR,
            'Should have failed but succeeded';
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 
            'Invalid contract'::VARCHAR,
            'PASS'::VARCHAR,
            'Correctly rejected: ' || SQLERRM;
    END;
END;
$$;
