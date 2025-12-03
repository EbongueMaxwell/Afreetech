-- ============================================
-- STORED PROCEDURE: sp_AddClient
-- Creates a new client with validation
-- ============================================

CREATE OR REPLACE PROCEDURE sp_addclient(
    -- Input parameters
    p_national_id VARCHAR(50),
    p_full_name VARCHAR(100),
    p_email VARCHAR(100),
    p_phone VARCHAR(20),
    p_address TEXT,
    p_date_of_birth DATE,
    p_agency_id INTEGER,
    p_created_by INTEGER,
    
    -- Output parameter
    OUT p_client_id INTEGER,
    OUT p_message VARCHAR(200)
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_agency_exists BOOLEAN;
    v_user_exists BOOLEAN;
    v_existing_client INTEGER;
BEGIN
    -- Initialize output
    p_client_id := 0;
    p_message := '';
    
    -- 1. VALIDATE REQUIRED FIELDS
    IF p_national_id IS NULL OR TRIM(p_national_id) = '' THEN
        p_message := 'National ID is required';
        RETURN;
    END IF;
    
    IF p_full_name IS NULL OR TRIM(p_full_name) = '' THEN
        p_message := 'Full name is required';
        RETURN;
    END IF;
    
    IF p_agency_id IS NULL THEN
        p_message := 'Agency ID is required';
        RETURN;
    END IF;
    
    -- 2. CHECK IF CLIENT ALREADY EXISTS (by national ID)
    SELECT client_id INTO v_existing_client
    FROM clients 
    WHERE national_id = p_national_id
    LIMIT 1;
    
    IF v_existing_client IS NOT NULL THEN
        p_message := 'Client with national ID ' || p_national_id || ' already exists';
        RETURN;
    END IF;
    
    -- 3. VALIDATE AGENCY EXISTS AND IS ACTIVE
    SELECT EXISTS (
        SELECT 1 FROM agencies 
        WHERE agency_id = p_agency_id 
        AND is_active = TRUE
    ) INTO v_agency_exists;
    
    IF NOT v_agency_exists THEN
        p_message := 'Agency ID ' || p_agency_id || ' does not exist or is inactive';
        RETURN;
    END IF;
    
    -- 4. VALIDATE CREATOR USER EXISTS (if provided)
    IF p_created_by IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM users 
            WHERE user_id = p_created_by 
            AND is_active = TRUE
        ) INTO v_user_exists;
        
        IF NOT v_user_exists THEN
            p_message := 'Creator user ID ' || p_created_by || ' does not exist or is inactive';
            RETURN;
        END IF;
    END IF;
    
    -- 5. VALIDATE EMAIL FORMAT (basic validation)
    IF p_email IS NOT NULL AND p_email != '' THEN
        IF p_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
            p_message := 'Invalid email format';
            RETURN;
        END IF;
        
        -- Check for duplicate email
        IF EXISTS (SELECT 1 FROM clients WHERE email = p_email AND email IS NOT NULL) THEN
            p_message := 'Email ' || p_email || ' is already registered';
            RETURN;
        END IF;
    END IF;
    
    -- 6. INSERT THE CLIENT
    INSERT INTO clients (
        national_id,
        full_name,
        email,
        phone,
        address,
        date_of_birth,
        agency_id,
        created_by,
        registration_date,
        status,
        created_at
    ) VALUES (
        UPPER(TRIM(p_national_id)),
        INITCAP(TRIM(p_full_name)),
        CASE WHEN p_email IS NOT NULL THEN LOWER(TRIM(p_email)) ELSE NULL END,
        TRIM(p_phone),
        TRIM(p_address),
        p_date_of_birth,
        p_agency_id,
        p_created_by,
        CURRENT_DATE,
        'ACTIVE',
        CURRENT_TIMESTAMP
    ) RETURNING client_id INTO p_client_id;
    
    -- 7. SET SUCCESS MESSAGE
    p_message := 'Client created successfully with ID: ' || p_client_id;
    
    -- 8. LOG THE ACTION (optional - if you have an audit table)
    -- INSERT INTO audit_logs (action_type, table_name, record_id, user_id)
    -- VALUES ('INSERT', 'clients', p_client_id, p_created_by);
    
EXCEPTION
    WHEN OTHERS THEN
        p_message := 'Error creating client: ' || SQLERRM;
        p_client_id := 0;
        RAISE NOTICE 'Error in sp_addclient: %', SQLERRM;
END;
$$;

-- ============================================
-- EXAMPLE USAGE
-- ============================================

/*
-- Example 1: Success case
DO $$
DECLARE
    v_client_id INTEGER;
    v_message VARCHAR(200);
BEGIN
    CALL sp_addclient(
        '123456789012',           -- national_id
        'John Doe',               -- full_name
        'john.doe@email.com',     -- email
        '+237123456789',          -- phone
        '123 Main Street, Douala',-- address
        '1990-05-15',             -- date_of_birth
        2,                        -- agency_id (Douala)
        1,                        -- created_by (user_id)
        v_client_id,              -- OUTPUT
        v_message                 -- OUTPUT
    );
    
    RAISE NOTICE 'Client ID: %, Message: %', v_client_id, v_message;
END $$;

-- Example 2: Error case (duplicate national ID)
DO $$
DECLARE
    v_client_id INTEGER;
    v_message VARCHAR(200);
BEGIN
    CALL sp_addclient(
        '123456789012',           -- Already exists
        'Jane Smith',
        'jane@email.com',
        '+237987654321',
        '456 Another Street',
        '1985-08-20',
        2,
        1,
        v_client_id,
        v_message
    );
    
    RAISE NOTICE 'Error Message: %', v_message;
END $$;

-- Example 3: Minimal required fields
DO $$
DECLARE
    v_client_id INTEGER;
    v_message VARCHAR(200);
BEGIN
    CALL sp_addclient(
        '987654321098',           -- national_id (required)
        'Alice Johnson',          -- full_name (required)
        NULL,                     -- email (optional)
        NULL,                     -- phone (optional)
        NULL,                     -- address (optional)
        NULL,                     -- date_of_birth (optional)
        3,                        -- agency_id (required)
        NULL,                     -- created_by (optional)
        v_client_id,
        v_message
    );
    
    RAISE NOTICE 'Client ID: %, Message: %', v_client_id, v_message;
END $$;
*/

-- ============================================
-- GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON PROCEDURE sp_addclient TO agency_manager, agency_staff;

-- ============================================
-- SIMPLIFIED VERSION (Minimal validation)
-- ============================================

/*
CREATE OR REPLACE PROCEDURE sp_addclient_simple(
    p_national_id VARCHAR(50),
    p_full_name VARCHAR(100),
    p_agency_id INTEGER,
    OUT p_client_id INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO clients (national_id, full_name, agency_id, status)
    VALUES (p_national_id, p_full_name, p_agency_id, 'ACTIVE')
    RETURNING client_id INTO p_client_id;
END;
$$;
*/
