#!/bin/bash

# Fix Secret Ownership for Helm
# This script resolves the issue where manually created secrets conflict with Helm deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-zoneapi}"
SECRET_NAME="${SECRET_NAME:-zoneapi-db-secret}"
RELEASE_NAME="${RELEASE_NAME:-zoneapi}"

echo -e "${BLUE}=== 🔧 HELM SECRET OWNERSHIP FIXER ===${NC}"
echo ""
echo "Namespace: $NAMESPACE"
echo "Secret: $SECRET_NAME"
echo "Release: $RELEASE_NAME"
echo ""

# Check kubectl connectivity
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Not connected to Kubernetes cluster${NC}"
    echo "Please run: az aks get-credentials --resource-group <rg> --name <cluster>"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}❌ Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

# Check if secret exists
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${YELLOW}ℹ️ Secret '$SECRET_NAME' does not exist in namespace '$NAMESPACE'${NC}"
    echo "Helm will create it during deployment."
    exit 0
fi

echo -e "${BLUE}ℹ️ Secret '$SECRET_NAME' exists, checking Helm metadata...${NC}"

# Check if secret has Helm labels
HELM_MANAGED=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")

if [ "$HELM_MANAGED" = "Helm" ]; then
    echo -e "${GREEN}✅ Secret is already managed by Helm${NC}"
    
    # Verify release name matches
    RELEASE_NAME_LABEL=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || echo "")
    
    if [ "$RELEASE_NAME_LABEL" = "$RELEASE_NAME" ]; then
        echo -e "${GREEN}✅ Secret belongs to correct Helm release: $RELEASE_NAME${NC}"
        echo "No action needed."
        exit 0
    else
        echo -e "${YELLOW}⚠️ Secret belongs to different release: $RELEASE_NAME_LABEL (expected: $RELEASE_NAME)${NC}"
        echo "This may cause conflicts. Consider manual intervention."
    fi
else
    echo -e "${YELLOW}⚠️ Secret is not managed by Helm (managed-by: '${HELM_MANAGED}')${NC}"
    echo "This will cause Helm deployment to fail."
    echo ""
    
    # Ask for confirmation
    read -p "Do you want to fix the secret ownership? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    echo -e "${BLUE}🔧 Fixing secret ownership...${NC}"
    
    # Get database password from environment or prompt
    if [ -z "$DB_PASSWORD" ]; then
        echo ""
        echo -e "${YELLOW}Database password needed to recreate secret.${NC}"
        echo "You can:"
        echo "1. Set DB_PASSWORD environment variable"
        echo "2. Enter password interactively"
        echo "3. Let the script retrieve from existing secret"
        echo ""
        
        read -p "Retrieve password from existing secret? (Y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo -n "Enter database password: "
            read -rs DB_PASSWORD
            echo
        else
            echo -e "${BLUE}📋 Retrieving password from existing secret...${NC}"
            DB_PASSWORD_B64=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null || echo "")
            
            if [ -n "$DB_PASSWORD_B64" ]; then
                DB_PASSWORD=$(echo "$DB_PASSWORD_B64" | base64 -d)
                echo -e "${GREEN}✅ Retrieved password from existing secret${NC}"
            else
                echo -e "${RED}❌ Could not retrieve password from existing secret${NC}"
                echo -n "Enter database password: "
                read -rs DB_PASSWORD
                echo
            fi
        fi
    fi
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}❌ Database password is required${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}🗑️ Deleting existing secret...${NC}"
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
    
    echo -e "${BLUE}🔨 Creating new secret with Helm metadata...${NC}"
    
    # Create secret with proper Helm metadata
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/instance: $RELEASE_NAME
    app.kubernetes.io/name: zoneapi
  annotations:
    meta.helm.sh/release-name: $RELEASE_NAME
    meta.helm.sh/release-namespace: $NAMESPACE
type: Opaque
data:
  password: $(echo -n "$DB_PASSWORD" | base64 -w 0)
EOF
    
    echo -e "${GREEN}✅ Secret recreated with proper Helm metadata${NC}"
    
    # Verify the fix
    echo -e "${BLUE}🔍 Verifying fix...${NC}"
    HELM_MANAGED_NEW=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
    RELEASE_NAME_NEW=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || echo "")
    
    if [ "$HELM_MANAGED_NEW" = "Helm" ] && [ "$RELEASE_NAME_NEW" = "$RELEASE_NAME" ]; then
        echo -e "${GREEN}✅ Fix verified successfully${NC}"
        echo "Helm deployment should now work correctly."
    else
        echo -e "${RED}❌ Fix verification failed${NC}"
        echo "Managed by: $HELM_MANAGED_NEW"
        echo "Release name: $RELEASE_NAME_NEW"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}🎉 Secret ownership fix completed successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Run your Helm deployment"
echo "2. Verify application starts correctly"
echo "3. Check pod status: kubectl get pods -n $NAMESPACE" 