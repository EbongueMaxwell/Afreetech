-- ============================================
-- STORED PROCEDURE: sp_GetStatsTransactions
-- Returns transaction statistics with filters
-- ============================================

CREATE OR REPLACE FUNCTION sp_getstatstransactions(
    p_agency_id INTEGER DEFAULT NULL,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE(
    total_transactions BIGINT,
    total_amount DECIMAL,
    avg_amount DECIMAL,
    min_amount DECIMAL,
    max_amount DECIMAL,
    successful_count BIGINT,
    failed_count BIGINT,
    pending_count BIGINT,
    by_transaction_type JSONB,
    by_agency JSONB,
    daily_avg DECIMAL
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH stats AS (
        SELECT 
            COUNT(*) as total_count,
            SUM(amount) as total_sum,
            AVG(amount) as total_avg,
            MIN(amount) as total_min,
            MAX(amount) as total_max,
            COUNT(CASE WHEN status = 'COMPLETED' THEN 1 END) as completed,
            COUNT(CASE WHEN status = 'FAILED' THEN 1 END) as failed,
            COUNT(CASE WHEN status = 'PENDING' THEN 1 END) as pending,
            AVG(CASE WHEN status = 'COMPLETED' THEN amount END) as daily_avg
        FROM transactions
        WHERE (p_agency_id IS NULL OR agency_id = p_agency_id)
          AND (p_start_date IS NULL OR transaction_date >= p_start_date)
          AND (p_end_date IS NULL OR transaction_date <= p_end_date + INTERVAL '1 day')
    ),
    type_stats AS (
        SELECT jsonb_object_agg(
            transaction_type, 
            jsonb_build_object(
                'count', COUNT(*),
                'total', SUM(amount)
            )
        ) as type_data
        FROM transactions
        WHERE (p_agency_id IS NULL OR agency_id = p_agency_id)
          AND (p_start_date IS NULL OR transaction_date >= p_start_date)
          AND (p_end_date IS NULL OR transaction_date <= p_end_date + INTERVAL '1 day')
    ),
    agency_stats AS (
        SELECT jsonb_object_agg(
            a.agency_name, 
            jsonb_build_object(
                'count', COUNT(t.transaction_id),
                'total', SUM(t.amount)
            )
        ) as agency_data
        FROM transactions t
        JOIN agencies a ON t.agency_id = a.agency_id
        WHERE (p_agency_id IS NULL OR t.agency_id = p_agency_id)
          AND (p_start_date IS NULL OR t.transaction_date >= p_start_date)
          AND (p_end_date IS NULL OR t.transaction_date <= p_end_date + INTERVAL '1 day')
        GROUP BY 1=1
    )
    SELECT 
        s.total_count,
        COALESCE(s.total_sum, 0),
        COALESCE(s.total_avg, 0),
        COALESCE(s.total_min, 0),
        COALESCE(s.total_max, 0),
        s.completed,
        s.failed,
        s.pending,
        COALESCE(t.type_data, '{}'::jsonb),
        COALESCE(ag.agency_data, '{}'::jsonb),
        COALESCE(s.daily_avg, 0)
    FROM stats s
    CROSS JOIN type_stats t
    CROSS JOIN agency_stats ag;
END;
$$;

-- ============================================
-- SIMPLE VERSION: Basic stats only
-- ============================================

CREATE OR REPLACE FUNCTION sp_getstatstransactions_simple()
RETURNS TABLE(
    total_transactions BIGINT,
    total_amount DECIMAL,
    today_transactions BIGINT,
    today_amount DECIMAL
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_count,
        SUM(amount) as total_sum,
        COUNT(CASE WHEN DATE(transaction_date) = CURRENT_DATE THEN 1 END) as today_count,
        SUM(CASE WHEN DATE(transaction_date) = CURRENT_DATE THEN amount ELSE 0 END) as today_sum
    FROM transactions
    WHERE status = 'COMPLETED';
END;
$$;

-- ============================================
-- VERSION 3: Stats by date range
-- ============================================

CREATE OR REPLACE FUNCTION sp_getstatstransactions_byperiod(
    p_period VARCHAR(10) DEFAULT 'MONTH'
)
RETURNS TABLE(
    period VARCHAR(20),
    transaction_count BIGINT,
    total_amount DECIMAL,
    avg_amount DECIMAL
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        CASE p_period
            WHEN 'DAY' THEN TO_CHAR(transaction_date, 'YYYY-MM-DD')
            WHEN 'WEEK' THEN TO_CHAR(transaction_date, 'YYYY-WW')
            WHEN 'MONTH' THEN TO_CHAR(transaction_date, 'YYYY-MM')
            ELSE TO_CHAR(transaction_date, 'YYYY-MM')
        END as period,
        COUNT(*) as count,
        SUM(amount) as total,
        AVG(amount) as average
    FROM transactions
    WHERE status = 'COMPLETED'
    GROUP BY 1
    ORDER BY 1 DESC
    LIMIT 10;
END;
$$;

-- ============================================
-- USAGE EXAMPLES
-- ============================================

/*
-- Example 1: All stats
SELECT * FROM sp_getstatstransactions();

-- Example 2: Douala agency stats
SELECT * FROM sp_getstatstransactions(2);

-- Example 3: Date range
SELECT * FROM sp_getstatstransactions(NULL, '2024-01-01', '2024-01-31');

-- Example 4: Simple version
SELECT * FROM sp_getstatstransactions_simple();

-- Example 5: By period
SELECT * FROM sp_getstatstransactions_byperiod('DAY');
SELECT * FROM sp_getstatstransactions_byperiod('WEEK');
SELECT * FROM sp_getstatstransactions_byperiod('MONTH');
*/

-- ============================================
-- GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION sp_getstatstransactions TO ceo_role, audit_role, agency_manager;
GRANT EXECUTE ON FUNCTION sp_getstatstransactions_simple TO agency_staff;
GRANT EXECUTE ON FUNCTION sp_getstatstransactions_byperiod TO ceo_role, audit_role;
