-- Minimal table definitions only
CREATE TABLE agencies (
    agency_id SERIAL PRIMARY KEY,
    agency_code VARCHAR(10) UNIQUE NOT NULL,
    agency_name VARCHAR(100) NOT NULL,
    city VARCHAR(50) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL,
    agency_id INTEGER REFERENCES agencies(agency_id),
    hashed_password VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE clients (
    client_id SERIAL PRIMARY KEY,
    national_id VARCHAR(50) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    agency_id INTEGER NOT NULL REFERENCES agencies(agency_id),
    status VARCHAR(20) DEFAULT 'ACTIVE'
);

CREATE TABLE contracts (
    contract_id SERIAL PRIMARY KEY,
    contract_number VARCHAR(30) UNIQUE NOT NULL,
    client_id INTEGER NOT NULL REFERENCES clients(client_id),
    agency_id INTEGER NOT NULL REFERENCES agencies(agency_id),
    contract_type VARCHAR(30) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'DRAFT'
);

CREATE TABLE transactions (
    transaction_id BIGSERIAL PRIMARY KEY,
    transaction_ref VARCHAR(50) UNIQUE NOT NULL,
    contract_id INTEGER NOT NULL REFERENCES contracts(contract_id),
    transaction_type VARCHAR(30) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    agency_id INTEGER NOT NULL REFERENCES agencies(agency_id),
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'PENDING'
);

CREATE TABLE roles (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL,
    role_code VARCHAR(20) UNIQUE NOT NULL
);

CREATE TABLE user_roles (
    user_role_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id),
    role_id INTEGER NOT NULL REFERENCES roles(role_id),
    UNIQUE(user_id, role_id)
);
