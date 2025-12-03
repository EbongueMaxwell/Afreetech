# Afreetech
Test Admin
📋 Prerequisites
Software Requirements:
PostgreSQL Server: Version 15 or higher

Operating System: Linux/Windows/macOS

Disk Space: Minimum 5GB

Memory: Minimum 2GB RAM

Configuration Requirements:
PostgreSQL service running

PostgreSQL superuser access (user: postgres)

Network access to PostgreSQL port (default: 5432)

PostgreSQL Configuration:
ini
# Minimum configuration in postgresql.conf:
shared_buffers = 128MB
work_mem = 8MB
max_connections = 100
🚀 Installation Procedure
Step 1: Database Creation
bash
# Login as PostgreSQL superuser
sudo -u postgres psql

# Create the database
CREATE DATABASE datacorp_db;
Step 2: Execution of SQL Scripts
Execute scripts in this order:

Create tables:

bash
psql -U postgres -d datacorp_db -f create_tables.sql
Create indexes:

bash
psql -U postgres -d datacorp_db -f create_indexes.sql
Create stored procedures:

bash
psql -U postgres -d datacorp_db -f stored_procedures.sql
Step 3: Creation of User Accounts
bash
# This is done automatically in stored_procedures.sql
# Default users created:
# - ceo_user (full access)
# - agency managers (per-agency access)
# - audit users (read-only + audit)
# - report users (read-only)
To verify users:

sql
\du  -- List all users
🔧 How to Launch Stored Procedure Tests
Test 1: Add a Client
sql
-- Connect to database
psql -U postgres -d datacorp_db

-- Test sp_AddClient
DO $$
DECLARE
    client_id INTEGER;
    msg VARCHAR;
BEGIN
    CALL sp_addclient('CM123456789', 'John Doe', NULL, NULL, 2, client_id, msg);
    RAISE NOTICE 'Client ID: %, Message: %', client_id, msg;
END $$;
Test 2: Get Clients by Agency
sql
-- Test sp_GetClientByAgence
SELECT * FROM sp_getclientbyagence(2);
Test 3: Add a Transaction
sql
-- Test sp_AddTransaction
DO $$
DECLARE
    txn_id BIGINT;
    txn_ref VARCHAR;
    msg VARCHAR;
BEGIN
    CALL sp_addtransaction(1, 'PAYMENT', 50000, 2, 3, txn_id, txn_ref, msg);
    RAISE NOTICE 'Transaction: %, Reference: %, Message: %', txn_id, txn_ref, msg;
END $$;
Test 4: Get Statistics
sql
-- Test sp_GetStatsTransactions
SELECT * FROM sp_getstatstransactions();
⚠️ Identify Common Problems
Problem 1: "Database does not exist"
Symptoms:

text
ERROR: database "datacorp_db" does not exist
Solution:

bash
# Create the database first
sudo -u postgres createdb datacorp_db
Problem 2: "Permission denied"
Symptoms:

text
ERROR: permission denied for schema public
Solution:

sql
-- Grant permissions
GRANT ALL ON DATABASE datacorp_db TO postgres;
GRANT ALL ON SCHEMA public TO postgres;
Problem 3: "Role does not exist"
Symptoms:

text
ERROR: role "username" does not exist
Solution:

sql
-- Create the user
CREATE USER username WITH PASSWORD 'password';
Problem 4: "Duplicate key violation"
Symptoms:

text
ERROR: duplicate key value violates unique constraint
Solution:

sql
-- Check existing data
SELECT * FROM table_name WHERE unique_field = 'value';
-- Delete or update duplicate
DELETE FROM table_name WHERE id = duplicate_id;
Problem 5: "Foreign key constraint"
Symptoms:

text
ERROR: insert or update on table violates foreign key constraint
Solution:

sql
-- Check if referenced data exists
SELECT * FROM parent_table WHERE id = referenced_id;
-- Insert missing parent record first
INSERT INTO parent_table (id, ...) VALUES (referenced_id, ...);
Problem 6: "Function does not exist"
Symptoms:

text
ERROR: function sp_addclient does not exist
Solution:

bash
# Re-run stored procedures script
psql -U postgres -d datacorp_db -f stored_procedures.sql
Problem 7: "Connection refused"
Symptoms:

text
psql: error: connection to server failed
Solution:

bash
# Start PostgreSQL service
sudo systemctl start postgresql
# Or on Windows: net start postgresql
🔍 Troubleshooting Checklist
Check PostgreSQL is running:

bash
systemctl status postgresql
Check database exists:

sql
\l
Check tables created:

sql
\dt
Check procedures exist:

sql
SELECT proname FROM pg_proc WHERE proname LIKE 'sp_%';
Check user permissions:

sql
\du username
📞 Support
If problems persist:

Check PostgreSQL logs: /var/log/postgresql/

Verify SQL script syntax

Ensure all scripts executed in correct order

Confirm PostgreSQL version compatibility

Quick Test:

bash
# Run a simple test
echo "SELECT version();" | psql -U postgres
