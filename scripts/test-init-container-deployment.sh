#!/bin/bash

# Test Init Container Deployment
# This script helps test the init container approach locally

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== 🧪 INIT CONTAINER DEPLOYMENT TEST ===${NC}"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."
for cmd in kubectl helm az; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}❌ $cmd is not installed${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✅ All prerequisites available${NC}"

# Check cluster connectivity
echo ""
echo "🔗 Checking cluster connectivity..."
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"
    CURRENT_CONTEXT=$(kubectl config current-context)
    echo "📍 Current context: $CURRENT_CONTEXT"
else
    echo -e "${RED}❌ Not connected to Kubernetes cluster${NC}"
    echo "Connect with: az aks get-credentials --resource-group <rg> --name <cluster>"
    exit 1
fi

# Get configuration values
echo ""
echo "🔧 Getting configuration values..."

# Try to get from Terraform
if [ -d "terraform" ]; then
    echo "📋 Reading from Terraform outputs..."
    cd terraform
    
    ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server 2>/dev/null || echo "")
    DB_HOST=$(terraform output -raw postgres_server_fqdn 2>/dev/null || echo "")
    
    cd ..
    
    if [ -n "$ACR_LOGIN_SERVER" ] && [ -n "$DB_HOST" ]; then
        echo -e "${GREEN}✅ Retrieved configuration from Terraform${NC}"
        echo "📍 ACR: $ACR_LOGIN_SERVER"
        echo "📍 Database: $DB_HOST"
    else
        echo -e "${YELLOW}⚠️ Could not get configuration from Terraform${NC}"
    fi
fi

# Manual input if needed
if [ -z "$ACR_LOGIN_SERVER" ]; then
    echo -n "Enter ACR login server: "
    read ACR_LOGIN_SERVER
fi

if [ -z "$DB_HOST" ]; then
    echo -n "Enter database host: "
    read DB_HOST
fi

if [ -z "$DB_PASSWORD" ]; then
    echo -n "Enter database password: "
    read -s DB_PASSWORD
    echo
fi

# Validate inputs
if [ -z "$ACR_LOGIN_SERVER" ] || [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}❌ Missing required configuration${NC}"
    exit 1
fi

# Set image details
IMAGE_TAG="latest"
IMAGE_REPO="$ACR_LOGIN_SERVER/zoneapi"

echo ""
echo "🚀 Deployment Configuration:"
echo "📍 Image: $IMAGE_REPO:$IMAGE_TAG"
echo "📍 Database: $DB_HOST"
echo "📍 Namespace: zoneapi"

# Clean up any existing deployment
echo ""
echo "🧹 Cleaning up existing deployment..."
helm uninstall zoneapi -n zoneapi --ignore-not-found 2>/dev/null || true
kubectl delete namespace zoneapi --ignore-not-found 2>/dev/null || true

echo "⏳ Waiting for cleanup to complete..."
sleep 10

# Deploy using Helm
echo ""
echo -e "${BLUE}🚀 Deploying with Init Container...${NC}"

helm upgrade --install zoneapi ./charts/zoneapi \
  --namespace zoneapi \
  --create-namespace \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  --set database.host="$DB_HOST" \
  --set database.password="$DB_PASSWORD" \
  --set livenessProbe.enabled=true \
  --set readinessProbe.enabled=true \
  --set replicaCount=1 \
  --wait --timeout=10m \
  --debug

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
else
    echo -e "${RED}❌ Deployment failed!${NC}"
    echo ""
    echo "🔍 Debugging information:"
    
    # Get pod status
    echo "📋 Pod Status:"
    kubectl get pods -n zoneapi -o wide
    
    # Get recent events
    echo ""
    echo "📋 Recent Events:"
    kubectl get events -n zoneapi --sort-by='.lastTimestamp' | tail -20
    
    # Get pod logs if available
    POD_NAME=$(kubectl get pods -n zoneapi -l app.kubernetes.io/name=zoneapi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD_NAME" ]; then
        echo ""
        echo "📋 Init Container Logs:"
        kubectl logs "$POD_NAME" -c migration -n zoneapi || echo "No init container logs available"
        
        echo ""
        echo "📋 Main Container Logs:"
        kubectl logs "$POD_NAME" -c zoneapi -n zoneapi || echo "No main container logs available"
        
        echo ""
        echo "📋 Pod Description:"
        kubectl describe pod "$POD_NAME" -n zoneapi
    fi
    
    exit 1
fi

# Validate deployment
echo ""
echo -e "${BLUE}🔍 Validating deployment...${NC}"

# Wait for pod to be ready
echo "⏳ Waiting for pod to be ready..."
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zoneapi -n zoneapi --timeout=300s; then
    echo -e "${GREEN}✅ Pod is ready!${NC}"
else
    echo -e "${RED}❌ Pod failed to become ready${NC}"
    exit 1
fi

# Get pod name
POD_NAME=$(kubectl get pods -n zoneapi -l app.kubernetes.io/name=zoneapi -o jsonpath='{.items[0].metadata.name}')

# Test health endpoint
echo ""
echo "🔍 Testing health endpoint..."
if kubectl exec -n zoneapi "$POD_NAME" -- curl -f --max-time 10 http://localhost:8080/health; then
    echo ""
    echo -e "${GREEN}✅ Health endpoint is working!${NC}"
else
    echo -e "${RED}❌ Health endpoint failed${NC}"
fi

# Show final status
echo ""
echo -e "${GREEN}🎉 Init Container Deployment Test Results:${NC}"
echo ""
kubectl get pods -n zoneapi -o wide
echo ""
kubectl get services -n zoneapi
echo ""

# Show access information
EXTERNAL_IP=$(kubectl get service zoneapi -n zoneapi -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
if [ "$EXTERNAL_IP" != "pending" ] && [ -n "$EXTERNAL_IP" ]; then
    echo -e "${GREEN}🌐 Application is accessible at:${NC}"
    echo "   Health: http://$EXTERNAL_IP/health"
    echo "   API: http://$EXTERNAL_IP/api/doctors"
else
    echo "⏳ LoadBalancer IP is still provisioning..."
fi

echo ""
echo -e "${GREEN}✅ Deployment test completed successfully!${NC}"
echo ""
echo "📋 Next steps:"
echo "1. Monitor the pods: kubectl get pods -n zoneapi -w"
echo "2. Check logs: kubectl logs -f deployment/zoneapi -c zoneapi -n zoneapi"
echo "3. Test API endpoints once LoadBalancer IP is ready" 