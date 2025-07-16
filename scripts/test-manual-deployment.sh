#!/bin/bash

# Manual Deployment Test Script
# This script tests each step of the CI/CD pipeline manually to ensure everything works
# before running the automated pipeline.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration - Update these values according to your setup
NAMESPACE="zoneapi"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-}"
ACR_NAME="${ACR_NAME:-}"
DB_HOST="${DB_HOST:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo -e "${BOLD}${BLUE}=== ZoneAPI Manual Deployment Test ===${NC}"
echo "This script will test each pipeline step manually"
echo "Make sure you have kubectl, az CLI, and helm installed"
echo ""

# Enhanced logging function
test_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u '+%H:%M:%S')

    case $level in
    "INFO")
        echo -e "${CYAN}[$timestamp] ℹ️  INFO:${NC} $message"
        ;;
    "SUCCESS")
        echo -e "${GREEN}[$timestamp] ✅ SUCCESS:${NC} $message"
        ;;
    "WARNING")
        echo -e "${YELLOW}[$timestamp] ⚠️  WARNING:${NC} $message"
        ;;
    "ERROR")
        echo -e "${RED}[$timestamp] ❌ ERROR:${NC} $message"
        ;;
    "STEP")
        echo -e "\n${BOLD}${PURPLE}=== STEP: $message ===${NC}"
        ;;
    *)
        echo -e "[$timestamp] $message"
        ;;
    esac
}

# Function to wait for user confirmation
wait_for_user() {
    echo -e "\n${YELLOW}Press Enter to continue or Ctrl+C to exit...${NC}"
    read -r
}

# Function to check prerequisites
check_prerequisites() {
    test_log "STEP" "CHECKING PREREQUISITES"
    
    # Check Azure CLI
    if command -v az &>/dev/null; then
        test_log "SUCCESS" "Azure CLI is installed"
        if az account show &>/dev/null; then
            test_log "SUCCESS" "Azure CLI is logged in"
            CURRENT_SUBSCRIPTION=$(az account show --query id --output tsv)
            test_log "INFO" "Current subscription: $CURRENT_SUBSCRIPTION"
        else
            test_log "ERROR" "Azure CLI not logged in. Run: az login"
            exit 1
        fi
    else
        test_log "ERROR" "Azure CLI not installed"
        exit 1
    fi
    
    # Check kubectl
    if command -v kubectl &>/dev/null; then
        test_log "SUCCESS" "kubectl is installed"
        if kubectl cluster-info &>/dev/null; then
            test_log "SUCCESS" "kubectl is connected to cluster"
            CURRENT_CONTEXT=$(kubectl config current-context)
            test_log "INFO" "Current context: $CURRENT_CONTEXT"
        else
            test_log "WARNING" "kubectl not connected to cluster"
        fi
    else
        test_log "ERROR" "kubectl not installed"
        exit 1
    fi
    
    # Check Helm
    if command -v helm &>/dev/null; then
        test_log "SUCCESS" "Helm is installed"
        HELM_VERSION=$(helm version --short)
        test_log "INFO" "Helm version: $HELM_VERSION"
    else
        test_log "ERROR" "Helm not installed"
        exit 1
    fi
}

# Function to get/set configuration values
get_configuration() {
    test_log "STEP" "GETTING CONFIGURATION VALUES"
    
    # Try to get values from Terraform if available
    if [ -f "terraform/terraform.tfstate" ] || [ -f "terraform/.terraform/terraform.tfstate" ]; then
        test_log "INFO" "Found Terraform state, attempting to get values..."
        cd terraform
        
        if terraform init -input=false &>/dev/null; then
            RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
            AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "")
            ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server 2>/dev/null || echo "")
            ACR_NAME=$(echo "$ACR_LOGIN_SERVER" | cut -d'.' -f1)
            DB_HOST=$(terraform output -raw postgres_server_fqdn 2>/dev/null || echo "")
            
            test_log "SUCCESS" "Retrieved values from Terraform"
        fi
        cd ..
    fi
    
    # Manual input for missing values
    if [ -z "$RESOURCE_GROUP" ]; then
        echo -n "Enter Resource Group name: "
        read -r RESOURCE_GROUP
    fi
    
    if [ -z "$AKS_CLUSTER_NAME" ]; then
        echo -n "Enter AKS Cluster name: "
        read -r AKS_CLUSTER_NAME
    fi
    
    if [ -z "$ACR_NAME" ]; then
        echo -n "Enter ACR name: "
        read -r ACR_NAME
    fi
    
    if [ -z "$DB_HOST" ]; then
        echo -n "Enter Database host: "
        read -r DB_HOST
    fi
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -n "Enter Database password: "
        read -rs DB_PASSWORD
        echo
    fi
    
    test_log "INFO" "Configuration:"
    test_log "INFO" "  Resource Group: $RESOURCE_GROUP"
    test_log "INFO" "  AKS Cluster: $AKS_CLUSTER_NAME"
    test_log "INFO" "  ACR Name: $ACR_NAME"
    test_log "INFO" "  Database Host: $DB_HOST"
    test_log "INFO" "  Database Password: [PROVIDED]"
    test_log "INFO" "  Image Tag: $IMAGE_TAG"
    test_log "INFO" "  Namespace: $NAMESPACE"
}

# Function to connect to AKS
connect_to_aks() {
    test_log "STEP" "CONNECTING TO AKS CLUSTER"
    
    test_log "INFO" "Getting AKS credentials..."
    if az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --overwrite-existing; then
        test_log "SUCCESS" "Connected to AKS cluster"
        
        # Verify connection
        if kubectl cluster-info &>/dev/null; then
            test_log "SUCCESS" "kubectl connection verified"
            kubectl get nodes
        else
            test_log "ERROR" "Failed to verify kubectl connection"
            exit 1
        fi
    else
        test_log "ERROR" "Failed to get AKS credentials"
        exit 1
    fi
}

# Function to create namespace and secrets
setup_namespace_and_secrets() {
    test_log "STEP" "SETTING UP NAMESPACE AND SECRETS"
    
    # Create namespace
    test_log "INFO" "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    test_log "SUCCESS" "Namespace '$NAMESPACE' ready"
    
    # Create database secret
    test_log "INFO" "Creating database secret..."
    kubectl create secret generic zoneapi-db-secret \
        --namespace="$NAMESPACE" \
        --from-literal=password="$DB_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    test_log "SUCCESS" "Database secret created"
    
    # Create ACR secret
    test_log "INFO" "Creating ACR secret..."
    ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query username --output tsv)
    ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query passwords[0].value --output tsv)
    ACR_LOGIN_SERVER="$ACR_NAME.azurecr.io"
    
    kubectl create secret docker-registry acr-secret \
        --namespace="$NAMESPACE" \
        --docker-server="$ACR_LOGIN_SERVER" \
        --docker-username="$ACR_USERNAME" \
        --docker-password="$ACR_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    test_log "SUCCESS" "ACR secret created"
    
    # Verify secrets
    test_log "INFO" "Verifying secrets..."
    kubectl get secrets -n "$NAMESPACE"
}

# Function to test database connectivity
test_database_connectivity() {
    test_log "STEP" "TESTING DATABASE CONNECTIVITY"
    
    test_log "INFO" "Creating database connectivity test pod..."
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: db-test-$(date +%s)
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  containers:
  - name: db-test
    image: postgres:15-alpine
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: zoneapi-db-secret
          key: password
    - name: DB_HOST
      value: "$DB_HOST"
    command:
    - /bin/sh
    - -c
    - |
      echo "Testing database connectivity to: \$DB_HOST"
      echo ""
      echo "Step 1: Testing DNS resolution..."
      nslookup "\$DB_HOST" || exit 1
      echo "✅ DNS resolution successful"
      
      echo ""
      echo "Step 2: Testing PostgreSQL connectivity..."
      pg_isready -h "\$DB_HOST" -p 5432 -U postgres || exit 1
      echo "✅ PostgreSQL service is ready"
      
      echo ""
      echo "Step 3: Testing authentication..."
      psql -h "\$DB_HOST" -U postgres -d postgres -c "SELECT version();" || exit 1
      echo "✅ Authentication successful"
      
      echo ""
      echo "Step 4: Testing/creating target database..."
      if ! psql -h "\$DB_HOST" -U postgres -d zone -c "SELECT current_database();" 2>/dev/null; then
        echo "Database 'zone' doesn't exist, creating it..."
        psql -h "\$DB_HOST" -U postgres -d postgres -c "CREATE DATABASE zone;" || exit 1
        echo "✅ Database 'zone' created"
      fi
      psql -h "\$DB_HOST" -U postgres -d zone -c "SELECT current_database();"
      echo "✅ Target database 'zone' accessible"
      
      echo ""
      echo "🎉 All database tests passed!"
EOF
    
    # Wait for pod to complete
    test_log "INFO" "Waiting for database test to complete..."
    DB_TEST_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep "db-test-" | tail -1 | awk '{print $1}')
    
    timeout=120
    while [ $timeout -gt 0 ]; do
        status=$(kubectl get pod "$DB_TEST_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$status" = "Succeeded" ]; then
            test_log "SUCCESS" "Database connectivity test passed"
            kubectl logs "$DB_TEST_POD" -n "$NAMESPACE"
            break
        elif [ "$status" = "Failed" ]; then
            test_log "ERROR" "Database connectivity test failed"
            kubectl logs "$DB_TEST_POD" -n "$NAMESPACE"
            kubectl describe pod "$DB_TEST_POD" -n "$NAMESPACE"
            exit 1
        fi
        echo -n "."
        sleep 5
        timeout=$((timeout - 5))
    done
    
    # Clean up test pod
    kubectl delete pod "$DB_TEST_POD" -n "$NAMESPACE" --ignore-not-found=true
    
    wait_for_user
}

# Function to test ACR image pull
test_acr_image_pull() {
    test_log "STEP" "TESTING ACR IMAGE PULL"
    
    FULL_IMAGE="$ACR_NAME.azurecr.io/zoneapi:$IMAGE_TAG"
    test_log "INFO" "Testing image pull: $FULL_IMAGE"
    
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: acr-test-$(date +%s)
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  imagePullSecrets:
  - name: acr-secret
  containers:
  - name: test
    image: $FULL_IMAGE
    command: ["/bin/sh", "-c", "echo 'Image pull successful'; ls -la /app/ || ls -la /out/ || ls -la /; exit 0"]
EOF
    
    # Wait for pod to start
    test_log "INFO" "Waiting for image pull test..."
    ACR_TEST_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep "acr-test-" | tail -1 | awk '{print $1}')
    
    sleep 10
    status=$(kubectl get pod "$ACR_TEST_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    if [ "$status" = "Succeeded" ] || [ "$status" = "Running" ]; then
        test_log "SUCCESS" "Image pull test successful"
        kubectl logs "$ACR_TEST_POD" -n "$NAMESPACE" || true
    else
        test_log "WARNING" "Image pull test status: $status"
        kubectl describe pod "$ACR_TEST_POD" -n "$NAMESPACE"
    fi
    
    # Clean up test pod
    kubectl delete pod "$ACR_TEST_POD" -n "$NAMESPACE" --ignore-not-found=true
    
    wait_for_user
}

# Function to run migration
run_migration() {
    test_log "STEP" "RUNNING DATABASE MIGRATION"
    
    test_log "INFO" "Deploying migration job using Helm..."
    
    # Deploy migration using Helm
    helm upgrade --install zoneapi-migration ./charts/zoneapi \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --set migration.enabled=true \
        --set debug.enabled=false \
        --set image.repository="$ACR_NAME.azurecr.io/zoneapi" \
        --set image.tag="$IMAGE_TAG" \
        --set imagePullSecrets[0].name=acr-secret \
        --set database.host="$DB_HOST" \
        --set database.password="$DB_PASSWORD" \
        --set database.port=5432 \
        --set database.name="zone" \
        --set database.user="postgres" \
        --set environment="Development" \
        --wait --timeout=5m \
        --debug
    
    test_log "SUCCESS" "Migration job deployed"
    
    # Monitor migration job
    test_log "INFO" "Monitoring migration job..."
    
    # Find the migration job
    MIGRATION_JOB=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$MIGRATION_JOB" ]; then
        # Fallback to find job by name pattern
        MIGRATION_JOB=$(kubectl get jobs -n "$NAMESPACE" --no-headers | grep "migration" | tail -1 | awk '{print $1}' || echo "")
    fi
    
    if [ -n "$MIGRATION_JOB" ]; then
        test_log "INFO" "Found migration job: $MIGRATION_JOB"
        
        # Wait for job completion
        test_log "INFO" "Waiting for migration to complete..."
        timeout=300  # 5 minutes
        while [ $timeout -gt 0 ]; do
            job_status=$(kubectl get job "$MIGRATION_JOB" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
            job_failed=$(kubectl get job "$MIGRATION_JOB" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
            
            if [ "$job_status" = "True" ]; then
                test_log "SUCCESS" "Migration completed successfully"
                kubectl logs -l job-name="$MIGRATION_JOB" -n "$NAMESPACE"
                break
            elif [ "$job_failed" = "True" ]; then
                test_log "ERROR" "Migration failed"
                kubectl logs -l job-name="$MIGRATION_JOB" -n "$NAMESPACE"
                kubectl describe job "$MIGRATION_JOB" -n "$NAMESPACE"
                exit 1
            fi
            
            echo -n "."
            sleep 10
            timeout=$((timeout - 10))
        done
        
        if [ $timeout -le 0 ]; then
            test_log "ERROR" "Migration timed out"
            exit 1
        fi
    else
        test_log "ERROR" "Migration job not found"
        kubectl get jobs -n "$NAMESPACE"
        exit 1
    fi
    
    wait_for_user
}

# Function to deploy application
deploy_application() {
    test_log "STEP" "DEPLOYING APPLICATION"
    
    test_log "INFO" "Deploying application using Helm..."
    
    # Deploy application (disable migration for application deployment)
    helm upgrade --install zoneapi ./charts/zoneapi \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --set migration.enabled=false \
        --set image.repository="$ACR_NAME.azurecr.io/zoneapi" \
        --set image.tag="$IMAGE_TAG" \
        --set imagePullSecrets[0].name=acr-secret \
        --set database.host="$DB_HOST" \
        --set database.password="$DB_PASSWORD" \
        --set database.port=5432 \
        --set database.name="zone" \
        --set database.user="postgres" \
        --set environment="Development" \
        --set livenessProbe.enabled=true \
        --set readinessProbe.enabled=true \
        --set replicaCount=1 \
        --wait --timeout=5m \
        --debug
    
    test_log "SUCCESS" "Application deployed"
    
    # Wait for pods to be ready
    test_log "INFO" "Waiting for application pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zoneapi -n "$NAMESPACE" --timeout=300s
    
    test_log "SUCCESS" "Application pods are ready"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi
    
    wait_for_user
}

# Function to test application health
test_application_health() {
    test_log "STEP" "TESTING APPLICATION HEALTH"
    
    # Get application pod
    APP_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$APP_POD" ]; then
        test_log "INFO" "Testing health endpoint on pod: $APP_POD"
        
        # Test health endpoint
        if kubectl exec -n "$NAMESPACE" "$APP_POD" -- curl -f --max-time 15 http://localhost:8080/health >/dev/null 2>&1; then
            test_log "SUCCESS" "Health endpoint is accessible"
            
            # Get health response
            health_response=$(kubectl exec -n "$NAMESPACE" "$APP_POD" -- curl -s http://localhost:8080/health)
            echo "Health Response: $health_response"
            
            # Check database connectivity in health response
            if echo "$health_response" | grep -q '"connected":true' || echo "$health_response" | grep -q 'Healthy'; then
                test_log "SUCCESS" "Database connectivity confirmed via health check"
            else
                test_log "WARNING" "Database connectivity unclear from health response"
            fi
        else
            test_log "ERROR" "Health endpoint not accessible"
            kubectl logs "$APP_POD" -n "$NAMESPACE" --tail=20
            exit 1
        fi
    else
        test_log "ERROR" "No application pod found"
        exit 1
    fi
    
    # Test API endpoints
    test_log "INFO" "Testing API endpoints..."
    if kubectl exec -n "$NAMESPACE" "$APP_POD" -- curl -f --max-time 10 http://localhost:8080/api/doctors >/dev/null 2>&1; then
        test_log "SUCCESS" "API endpoints are accessible"
    else
        test_log "WARNING" "API endpoint test failed (may be expected with empty database)"
    fi
    
    wait_for_user
}

# Function to show final status
show_final_status() {
    test_log "STEP" "FINAL STATUS AND RECOMMENDATIONS"
    
    echo -e "\n${GREEN}🎉 Manual deployment test completed successfully!${NC}"
    echo ""
    echo -e "${BOLD}Resources created:${NC}"
    kubectl get all -n "$NAMESPACE"
    
    echo ""
    echo -e "${BOLD}Services:${NC}"
    kubectl get services -n "$NAMESPACE"
    
    echo ""
    echo -e "${BOLD}Migration Jobs:${NC}"
    kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration
    
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    test_log "INFO" "1. All manual tests passed - your pipeline should now work"
    test_log "INFO" "2. Push your changes to trigger the automated pipeline"
    test_log "INFO" "3. Monitor the pipeline using: kubectl get all -n $NAMESPACE -w"
    test_log "INFO" "4. Access application health: kubectl port-forward svc/zoneapi 8080:8080 -n $NAMESPACE"
    
    echo ""
    echo -e "${YELLOW}Configuration Summary:${NC}"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "AKS Cluster: $AKS_CLUSTER_NAME"
    echo "ACR: $ACR_NAME.azurecr.io"
    echo "Database: $DB_HOST"
    echo "Namespace: $NAMESPACE"
    echo "Image: $ACR_NAME.azurecr.io/zoneapi:$IMAGE_TAG"
}

# Main execution
main() {
    check_prerequisites
    get_configuration
    connect_to_aks
    setup_namespace_and_secrets
    test_database_connectivity
    test_acr_image_pull
    run_migration
    deploy_application
    test_application_health
    show_final_status
}

# Run main function
main "$@" 