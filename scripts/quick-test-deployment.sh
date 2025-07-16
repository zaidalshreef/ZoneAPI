#!/bin/bash

# Quick Deployment Test Script
# For testing deployment configuration locally

set -e

# Configuration
NAMESPACE="${NAMESPACE:-zoneapi}"
ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:-acrzoneapidevpaffv359.azurecr.io}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DB_HOST="${DB_HOST:-psql-zoneapi-dev-paffv359.postgres.database.azure.com}"
DB_PASSWORD="${DB_PASSWORD:-ID8SUGEEXXSVkBncVKFRXw9iZ}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Quick ZoneAPI Deployment Test ===${NC}"
echo "Namespace: $NAMESPACE"
echo "ACR: $ACR_LOGIN_SERVER"
echo "Image Tag: $IMAGE_TAG"
echo "Database Host: $DB_HOST"
echo ""

# Deploy using Helm with the correct configuration
echo -e "${YELLOW}Deploying application...${NC}"

helm upgrade --install zoneapi ./charts/zoneapi \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set migration.enabled=false \
    --set image.repository="$ACR_LOGIN_SERVER/zoneapi" \
    --set image.tag="$IMAGE_TAG" \
    --set imagePullSecrets[0].name=acr-secret \
    --set database.host="$DB_HOST" \
    --set database.password="$DB_PASSWORD" \
    --set livenessProbe.enabled=true \
    --set readinessProbe.enabled=true \
    --set replicaCount=1 \
    --force \
    --wait --timeout=3m

echo -e "${GREEN}✅ Deployment completed!${NC}"
echo ""

# Run validation
echo -e "${YELLOW}Running validation...${NC}"
chmod +x ./scripts/validate-deployment.sh
./scripts/validate-deployment.sh

echo ""
echo -e "${GREEN}🎉 Quick deployment test completed successfully!${NC}"
