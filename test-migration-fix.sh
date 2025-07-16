#!/bin/bash

# Test script to validate migration fix
echo "=== Testing Migration Fix ==="

# Source the functions from run-migration.sh
source ./scripts/run-migration.sh

# Test environment variables
export NAMESPACE="zoneapi"
export DB_PASSWORD="ID8SUGEEXXSVkBncVKFRXw9iZ"
export DATABASE_HOST="psql-zoneapi-dev-paffv359.postgres.database.azure.com"
export ACR_LOGIN_SERVER="acrzoneapidevpaffv359.azurecr.io"
export IMAGE_TAG="latest"

echo "Environment variables:"
echo "- NAMESPACE: $NAMESPACE"
echo "- DATABASE_HOST: $DATABASE_HOST"
echo "- ACR_LOGIN_SERVER: $ACR_LOGIN_SERVER"
echo "- IMAGE_TAG: $IMAGE_TAG"
echo "- DB_PASSWORD: [SET]"
echo ""

echo "Testing cleanup_failed_migrations function..."
cleanup_failed_migrations

echo ""
echo "Testing update_database_secret function..."
update_database_secret "$DB_PASSWORD"

echo ""
echo "=== Test completed ==="
echo "If no errors occurred, the migration fix should work!"
echo ""
echo "Next steps:"
echo "1. Commit and push these changes"
echo "2. Re-run your GitHub Actions workflow"
echo "3. The migration should succeed in ~1 minute"
