-- Database initialization script for ZoneAPI local testing
-- This script runs when the PostgreSQL container starts

-- Create the database (if not exists)
SELECT 'CREATE DATABASE zone' 
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'zone');

-- Connect to the zone database
\c zone;

-- Create extensions if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Set timezone
SET timezone = 'UTC';

-- Create a test user for local development (optional)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'zoneapi_user') THEN
        CREATE USER zoneapi_user WITH PASSWORD 'zoneapi_pass';
        GRANT ALL PRIVILEGES ON DATABASE zone TO zoneapi_user;
    END IF;
END
$$;

-- Log successful initialization
SELECT 'ZoneAPI database initialized successfully' AS message; 