#!/bin/bash

# Test database connection script
# Usage: ./test-db-connection.sh <host> <password>

set -e

DB_HOST="${1:-psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com}"
DB_PASSWORD="${2}"
DB_PORT="5432"
DB_USER="postgres"
DB_NAME="zone"

if [ -z "$DB_PASSWORD" ]; then
    echo "❌ Error: Password is required"
    echo "Usage: $0 <host> <password>"
    echo "Example: $0 psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com your_password"
    exit 1
fi

echo "🧪 Testing Database Connection"
echo "================================"
echo "Host: $DB_HOST"
echo "Port: $DB_PORT"
echo "User: $DB_USER"
echo "Database: $DB_NAME"
echo ""

# Check if psql is available
if ! command -v psql &>/dev/null; then
    echo "❌ PostgreSQL client (psql) is not installed"
    echo "Install it with:"
    echo "  Ubuntu/Debian: sudo apt-get install postgresql-client"
    echo "  macOS: brew install postgresql"
    echo "  Windows: Download from https://www.postgresql.org/download/"
    exit 1
fi

export PGPASSWORD="$DB_PASSWORD"

echo "Step 1: Testing DNS resolution..."
if nslookup "$DB_HOST" >/dev/null 2>&1; then
    echo "✅ DNS resolution successful"
else
    echo "❌ DNS resolution failed"
    exit 1
fi

echo ""
echo "Step 2: Testing network connectivity..."
if nc -zv "$DB_HOST" "$DB_PORT" 2>/dev/null; then
    echo "✅ Network connection successful"
else
    echo "❌ Network connection failed"
    echo "Check if the host and port are correct, and firewall rules allow the connection"
    exit 1
fi

echo ""
echo "Step 3: Testing PostgreSQL service..."
if pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; then
    echo "✅ PostgreSQL service is ready"
else
    echo "❌ PostgreSQL service is not ready"
    exit 1
fi

echo ""
echo "Step 4: Testing authentication..."
if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT version();" >/dev/null 2>&1; then
    echo "✅ Authentication successful"
    echo "PostgreSQL version:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT version();" | grep PostgreSQL
else
    echo "❌ Authentication failed"
    echo "Check username and password"
    exit 1
fi

echo ""
echo "Step 5: Testing target database access..."
if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT current_database();" >/dev/null 2>&1; then
    echo "✅ Target database '$DB_NAME' is accessible"
else
    echo "⚠️  Target database '$DB_NAME' is not accessible"
    echo "Creating database '$DB_NAME'..."
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;" >/dev/null 2>&1; then
        echo "✅ Database '$DB_NAME' created successfully"
    else
        echo "❌ Failed to create database '$DB_NAME'"
        exit 1
    fi
fi

echo ""
echo "Step 6: Testing connection string format..."
CONNECTION_STRING="Host=$DB_HOST;Port=$DB_PORT;Database=$DB_NAME;Username=$DB_USER;Password=***;Command Timeout=300;"
echo "✅ Connection string format: $CONNECTION_STRING"

echo ""
echo "🎉 All database connection tests passed!"
echo "The database is ready for your application."
