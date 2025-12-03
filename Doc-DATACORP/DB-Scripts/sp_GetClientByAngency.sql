-- ============================================
-- STORED PROCEDURE: sp_GetClientByAgence
-- Retrieves clients filtered by agency with options
-- ============================================

CREATE OR REPLACE FUNCTION sp_getclientbyagence(
    -- Input parameters
    p_agency_id INTEGER,
    p_status VARCHAR(20) DEFAULT NULL,
    p_search_term VARCHAR(100) DEFAULT NULL,
    p_limit INTEGER DEFAULT 100,
    p_offset INTEGER DEFAULT 0,
    p_sort_by VARCHAR(30) DEFAULT 'full_name',
    p_sort_order VARCHAR(4) DEFAULT 'ASC'
)
RETURNS TABLE(
    client_id INTEGER,
    national_id VARCHAR(50),
    full_name VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(20),
    address TEXT,
    date_of_birth DATE,
    age INTEGER,
    registration_date DATE,
    status VARCHAR(20),
    agency_name VARCHAR(100),
    agency_code VARCHAR(10),
    city VARCHAR(50),
    days_since_registration INTEGER,
    created_by_user VARCHAR(100)
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sort_sql VARCHAR(500);
    v_agency_exists BOOLEAN;
BEGIN
    -- 1. VALIDATE AGENCY EXISTS
    SELECT EXISTS (
        SELECT 1 FROM agencies 
        WHERE agency_id = p_agency_id 
        AND is_active = TRUE
    ) INTO v_agency_exists;
    
    IF NOT v_agency_exists THEN
        RAISE EXCEPTION 'Agency ID % does not exist or is inactive', p_agency_id;
    END IF;
    
    -- 2. VALIDATE SORT PARAMETERS
    IF p_sort_order NOT IN ('ASC', 'DESC') THEN
        RAISE EXCEPTION 'Sort order must be ASC or DESC';
    END IF;
    
    -- 3. BUILD DYNAMIC SORT CLAUSE
    CASE p_sort_by
        WHEN 'full_name' THEN v_sort_sql := 'c.full_name';
        WHEN 'registration_date' THEN v_sort_sql := 'c.registration_date';
        WHEN 'national_id' THEN v_sort_sql := 'c.national_id';
        WHEN 'status' THEN v_sort_sql := 'c.status';
        WHEN 'date_of_birth' THEN v_sort_sql := 'c.date_of_birth';
        ELSE v_sort_sql := 'c.full_name'; -- Default
    END CASE;
    
    -- 4. RETURN QUERY WITH FILTERS
    RETURN QUERY EXECUTE format('
        SELECT 
            c.client_id,
            c.national_id,
            c.full_name,
            c.email,
            c.phone,
            c.address,
            c.date_of_birth,
            EXTRACT(YEAR FROM AGE(CURRENT_DATE, c.date_of_birth))::INTEGER as age,
            c.registration_date,
            c.status,
            a.agency_name,
            a.agency_code,
            a.city,
            (CURRENT_DATE - c.registration_date)::INTEGER as days_since_registration,
            u.full_name as created_by_user
        FROM clients c
        INNER JOIN agencies a ON c.agency_id = a.agency_id
        LEFT JOIN users u ON c.created_by = u.user_id
        WHERE c.agency_id = $1
            AND ($2 IS NULL OR c.status = $2)
            AND (
                $3 IS NULL 
                OR c.national_id ILIKE $3
                OR c.full_name ILIKE $3
                OR c.email ILIKE $3
                OR c.phone ILIKE $3
            )
        ORDER BY %s %s
        LIMIT $4
        OFFSET $5',
        v_sort_sql, p_sort_order
    ) USING p_agency_id, p_status, 
           CASE WHEN p_search_term IS NOT NULL THEN '%' || p_search_term || '%' END,
           p_limit, p_offset;
    
    -- Log for monitoring (optional)
    RAISE NOTICE 'Retrieved clients for agency ID: % with filters: status=%, search=%', 
        p_agency_id, p_status, p_search_term;
    
END;
$$;

-- ============================================
-- ALTERNATIVE VERSION: Simple with counts
-- ============================================

CREATE OR REPLACE FUNCTION sp_getclientbyagence_withcount(
    p_agency_id INTEGER,
    p_status VARCHAR(20) DEFAULT NULL
)
RETURNS TABLE(
    client_id INTEGER,
    national_id VARCHAR(50),
    full_name VARCHAR(100),
    status VARCHAR(20),
    registration_date DATE,
    total_clients BIGINT,
    active_clients BIGINT,
    inactive_clients BIGINT
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.client_id,
        c.national_id,
        c.full_name,
        c.status,
        c.registration_date,
        (SELECT COUNT(*) FROM clients WHERE agency_id = p_agency_id) as total_clients,
        (SELECT COUNT(*) FROM clients WHERE agency_id = p_agency_id AND status = 'ACTIVE') as active_clients,
        (SELECT COUNT(*) FROM clients WHERE agency_id = p_agency_id AND status = 'INACTIVE') as inactive_clients
    FROM clients c
    WHERE c.agency_id = p_agency_id
        AND (p_status IS NULL OR c.status = p_status)
    ORDER BY c.full_name;
END;
$$;

-- ============================================
-- VERSION 3: Get clients with contracts summary
-- ============================================

CREATE OR REPLACE FUNCTION sp_getclientbyagence_contracts(
    p_agency_id INTEGER
)
RETURNS TABLE(
    client_id INTEGER,
    national_id VARCHAR(50),
    full_name VARCHAR(100),
    total_contracts BIGINT,
    active_contracts BIGINT,
    total_contract_value DECIMAL(15,2),
    last_contract_date DATE,
    first_contract_date DATE
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.client_id,
        c.national_id,
        c.full_name,
        COUNT(ct.contract_id) as total_contracts,
        COUNT(CASE WHEN ct.status = 'ACTIVE' THEN 1 END) as active_contracts,
        COALESCE(SUM(ct.amount), 0) as total_contract_value,
        MAX(ct.start_date) as last_contract_date,
        MIN(ct.start_date) as first_contract_date
    FROM clients c
    LEFT JOIN contracts ct ON c.client_id = ct.client_id
    WHERE c.agency_id = p_agency_id
    GROUP BY c.client_id, c.national_id, c.full_name
    ORDER BY c.full_name;
END;
$$;

-- ============================================
-- VERSION 4: Get client statistics by agency
-- ============================================

CREATE OR REPLACE FUNCTION sp_getclientstatsbyagence(
    p_agency_id INTEGER
)
RETURNS TABLE(
    agency_name VARCHAR(100),
    total_clients BIGINT,
    active_clients BIGINT,
    inactive_clients BIGINT,
    suspended_clients BIGINT,
    avg_client_age DECIMAL(5,1),
    oldest_registration DATE,
    newest_registration DATE,
    clients_last_30_days BIGINT
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.agency_name,
        COUNT(c.client_id) as total_clients,
        COUNT(CASE WHEN c.status = 'ACTIVE' THEN 1 END) as active_clients,
        COUNT(CASE WHEN c.status = 'INACTIVE' THEN 1 END) as inactive_clients,
        COUNT(CASE WHEN c.status = 'SUSPENDED' THEN 1 END) as suspended_clients,
        AVG(EXTRACT(YEAR FROM AGE(CURRENT_DATE, c.date_of_birth))) as avg_client_age,
        MIN(c.registration_date) as oldest_registration,
        MAX(c.registration_date) as newest_registration,
        COUNT(CASE WHEN c.registration_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as clients_last_30_days
    FROM agencies a
    LEFT JOIN clients c ON a.agency_id = c.agency_id
    WHERE a.agency_id = p_agency_id
    GROUP BY a.agency_name;
END;
$$;

-- ============================================
-- USAGE EXAMPLES
-- ============================================

/*
-- Example 1: Get all clients from Douala agency (agency_id = 2)
SELECT * FROM sp_getclientbyagence(2);

-- Example 2: Get only active clients with search
SELECT * FROM sp_getclientbyagence(
    2,                         -- agency_id
    'ACTIVE',                  -- status filter
    'john',                    -- search term (name, email, phone, national_id)
    50,                        -- limit to 50 records
    0,                         -- offset (for pagination)
    'registration_date',       -- sort by registration date
    'DESC'                     -- sort order
);

-- Example 3: Get clients with counts
SELECT * FROM sp_getclientbyagence_withcount(2, 'ACTIVE');

-- Example 4: Get clients with contracts info
SELECT * FROM sp_getclientbyagence_contracts(2);

-- Example 5: Get agency client statistics
SELECT * FROM sp_getclientstatsbyagence(2);

-- Example 6: Pagination example
-- Page 1
SELECT * FROM sp_getclientbyagence(2, NULL, NULL, 20, 0);
-- Page 2
SELECT * FROM sp_getclientbyagence(2, NULL, NULL, 20, 20);
-- Page 3
SELECT * FROM sp_getclientbyagence(2, NULL, NULL, 20, 40);

-- Example 7: Get specific fields only
SELECT 
    client_id,
    full_name,
    phone,
    registration_date
FROM sp_getclientbyagence(2)
WHERE status = 'ACTIVE'
ORDER BY full_name;
*/

-- ============================================
-- GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION sp_getclientbyagence TO ceo_role, agency_manager, agency_staff, audit_role;
GRANT EXECUTE ON FUNCTION sp_getclientbyagence_withcount TO ceo_role, agency_manager, audit_role;
GRANT EXECUTE ON FUNCTION sp_getclientbyagence_contracts TO ceo_role, agency_manager;
GRANT EXECUTE ON FUNCTION sp_getclientstatsbyagence TO ceo_role, audit_role;

-- ============================================
-- TEST DATA SETUP
-- ============================================

/*
-- Insert test clients for Douala agency (agency_id = 2)
INSERT INTO clients (national_id, full_name, email, phone, agency_id, status) VALUES
('CM123456001', 'Jean Dupont', 'jean@email.com', '+237699000001', 2, 'ACTIVE'),
('CM123456002', 'Marie Curie', 'marie@email.com', '+237699000002', 2, 'ACTIVE'),
('CM123456003', 'Paul Martin', 'paul@email.com', '+237699000003', 2, 'INACTIVE'),
('CM123456004', 'Sophie Laurent', 'sophie@email.com', '+237699000004', 2, 'ACTIVE'),
('CM123456005', 'Thomas Bernard', 'thomas@email.com', '+237699000005', 2, 'SUSPENDED');

-- Test the procedures
SELECT * FROM sp_getclientbyagence(2);
SELECT * FROM sp_getclientbyagence_withcount(2);
SELECT * FROM sp_getclientstatsbyagence(2);
*/
