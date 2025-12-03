-- ============================================
-- USER CREATION & ROLE ATTRIBUTION
-- PostgreSQL Database: datacorp_db
-- ============================================

-- 1. CREATE DATABASE ROLES (GROUPS)
CREATE ROLE ceo_role;
CREATE ROLE audit_role;
CREATE ROLE agency_manager_role;
CREATE ROLE agency_staff_role;
CREATE ROLE report_role;

-- 2. CREATE SPECIFIC USERS
-- CEO User (Full access)
CREATE USER ceo_user WITH PASSWORD 'CEO_Pass123!';
ALTER USER ceo_user SET search_path = public;

-- Audit Team Users (Read-only + audit logging)
CREATE USER audit_lead WITH PASSWORD 'Audit_Lead123!';
CREATE USER auditor1 WITH PASSWORD 'Auditor1_Pass!';

-- Agency Managers (One per agency)
CREATE USER douala_manager WITH PASSWORD 'Douala_Mgr123!';
CREATE USER yaounde_manager WITH PASSWORD 'Yaounde_Mgr123!';
CREATE USER bafoussam_manager WITH PASSWORD 'Bafoussam_Mgr123!';

-- Agency Staff (Example users)
CREATE USER douala_staff1 WITH PASSWORD 'Staff1_Douala!';
CREATE USER yaounde_staff1 WITH PASSWORD 'Staff1_Yaounde!';

-- Report User (Read-only for reports)
CREATE USER report_user WITH PASSWORD 'Report_User123!';

-- 3. GRANT CONNECTIONS TO DATABASE
GRANT CONNECT ON DATABASE datacorp_db TO 
    ceo_user,
    audit_lead, auditor1,
    douala_manager, yaounde_manager, bafoussam_manager,
    douala_staff1, yaounde_staff1,
    report_user;

-- 4. GRANT SCHEMA USAGE
GRANT USAGE ON SCHEMA public TO 
    ceo_role, audit_role, agency_manager_role, agency_staff_role, report_role;

-- 5. ASSIGN PERMISSIONS TO ROLES

-- CEO ROLE: Full access
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ceo_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ceo_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ceo_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO ceo_role;

-- AUDIT ROLE: Read-only + audit log insert
GRANT SELECT ON ALL TABLES IN SCHEMA public TO audit_role;
GRANT INSERT ON audit_logs TO audit_role;
GRANT SELECT ON pg_stat_activity TO audit_role;
GRANT EXECUTE ON FUNCTION sp_getstatstransactions TO audit_role;
GRANT EXECUTE ON FUNCTION sp_getclientbyagence TO audit_role;

-- AGENCY MANAGER ROLE: Manage own agency data
GRANT SELECT, INSERT, UPDATE ON 
    clients, contracts, transactions, users 
TO agency_manager_role;

GRANT SELECT ON agencies TO agency_manager_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO agency_manager_role;
GRANT EXECUTE ON PROCEDURE sp_addclient TO agency_manager_role;
GRANT EXECUTE ON PROCEDURE sp_addtransaction TO agency_manager_role;
GRANT EXECUTE ON FUNCTION sp_getclientbyagence TO agency_manager_role;

-- AGENCY STAFF ROLE: Limited operations
GRANT SELECT ON 
    clients, contracts, transactions, agencies 
TO agency_staff_role;

GRANT INSERT, UPDATE ON 
    clients, transactions 
TO agency_staff_role;

GRANT EXECUTE ON PROCEDURE sp_addclient TO agency_staff_role;
GRANT EXECUTE ON PROCEDURE sp_addtransaction_simple TO agency_staff_role;

-- REPORT ROLE: Read-only for reporting
GRANT SELECT ON ALL TABLES IN SCHEMA public TO report_role;
GRANT EXECUTE ON FUNCTION sp_getstatstransactions_simple TO report_role;

-- 6. ASSIGN USERS TO ROLES
-- CEO
GRANT ceo_role TO ceo_user;

-- Audit Team
GRANT audit_role TO audit_lead, auditor1;

-- Agency Managers
GRANT agency_manager_role TO douala_manager, yaounde_manager, bafoussam_manager;

-- Agency Staff
GRANT agency_staff_role TO douala_staff1, yaounde_staff1;

-- Report User
GRANT report_role TO report_user;

-- 7. SET ROW LEVEL SECURITY (Optional)
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- Policy for agency isolation
CREATE POLICY agency_isolation ON clients
    USING (agency_id = current_setting('app.current_agency_id')::INTEGER);

CREATE POLICY agency_isolation ON contracts
    USING (agency_id = current_setting('app.current_agency_id')::INTEGER);

CREATE POLICY agency_isolation ON transactions
    USING (agency_id = current_setting('app.current_agency_id')::INTEGER);

-- 8. CREATE CONFIGURATION FUNCTION
CREATE OR REPLACE FUNCTION set_user_context(
    p_user_id INTEGER,
    p_agency_id INTEGER
) 
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM set_config('app.current_user_id', p_user_id::TEXT, FALSE);
    PERFORM set_config('app.current_agency_id', p_agency_id::TEXT, FALSE);
END;
$$;

-- 9. REVOKE PUBLIC ACCESS
REVOKE ALL ON DATABASE datacorp_db FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;

-- ============================================
-- QUICK CHECK COMMANDS
-- ============================================

-- List all users
SELECT usename AS username, usesysid AS user_id FROM pg_user ORDER BY usename;

-- List all roles
SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%' ORDER BY rolname;

-- Check user permissions
SELECT 
    grantee,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('ceo_role', 'audit_role', 'agency_manager_role', 'agency_staff_role')
ORDER BY grantee, table_name;

-- ============================================
-- MINIMAL VERSION (Essential only)
-- ============================================

/*
-- Create essential users
CREATE USER ceo_user WITH PASSWORD 'StrongPass123!';
CREATE USER auditor WITH PASSWORD 'AuditPass123!';
CREATE USER agency_user WITH PASSWORD 'AgencyPass123!';

-- Create roles
CREATE ROLE ceo_role;
CREATE ROLE audit_role;
CREATE ROLE agency_role;

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO ceo_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO audit_role;
GRANT SELECT, INSERT, UPDATE ON clients, contracts, transactions TO agency_role;

-- Assign roles
GRANT ceo_role TO ceo_user;
GRANT audit_role TO auditor;
GRANT agency_role TO agency_user;
*/

-- ============================================
-- PASSWORD POLICY ENFORCEMENT
-- ============================================

-- Set password expiration (requires passwordcheck extension)
-- CREATE EXTENSION IF NOT EXISTS passwordcheck;

-- Set password policies in postgresql.conf:
-- password_encryption = scram-sha-256
-- shared_preload_libraries = 'passwordcheck'
