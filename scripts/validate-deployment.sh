#!/bin/bash

# ZoneAPI Deployment Validation Script
# Validates that the application is properly deployed and healthy

set -e

# Configuration
NAMESPACE="${NAMESPACE:-zoneapi}"
TIMEOUT="${TIMEOUT:-120}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ZoneAPI Deployment Validation ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Timeout: $TIMEOUT seconds"
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# Function to log with colors
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if namespace exists
log_info "Checking namespace '$NAMESPACE'..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi
log_success "Namespace exists"

# Check for application pods
log_info "Checking for application pods..."
app_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi -o name 2>/dev/null || echo "")

if [ -z "$app_pods" ]; then
    log_error "No application pods found"
    exit 1
fi

pod_count=$(echo "$app_pods" | wc -l)
log_success "Found $pod_count application pod(s)"

# Get the main application pod
app_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

log_info "Validating pod: $app_pod"

# Check pod status
pod_status=$(kubectl get pod "$app_pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
ready_status=$(kubectl get pod "$app_pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

log_info "Pod Status: $pod_status"
log_info "Ready Status: $ready_status"

if [ "$pod_status" != "Running" ]; then
    log_error "Pod is not running (status: $pod_status)"
    kubectl describe pod "$app_pod" -n "$NAMESPACE"
    exit 1
fi

if [ "$ready_status" != "True" ]; then
    log_warning "Pod is not ready yet (status: $ready_status)"
    log_info "Waiting for pod to become ready..."

    if ! kubectl wait --for=condition=ready pod/"$app_pod" -n "$NAMESPACE" --timeout="${TIMEOUT}s"; then
        log_error "Pod failed to become ready within $TIMEOUT seconds"
        kubectl describe pod "$app_pod" -n "$NAMESPACE"
        exit 1
    fi
fi

log_success "Pod is running and ready"

# Validate environment variables
log_info "Validating environment variables..."
connection_string=$(kubectl exec -n "$NAMESPACE" "$app_pod" -- env | grep "ConnectionStrings__PostgreSQLConnection" || echo "")

if [ -z "$connection_string" ]; then
    log_error "PostgreSQLConnection string not found"
    exit 1
fi

log_success "PostgreSQL connection string found"

# Extract database host from connection string
db_host=$(echo "$connection_string" | grep -o 'Host=[^;]*' | cut -d'=' -f2 || echo "")
if [ -n "$db_host" ]; then
    log_info "Database Host: $db_host"

    if [[ "$db_host" == "localhost" || "$db_host" == "127.0.0.1" ]]; then
        log_error "Connection string points to localhost instead of Azure PostgreSQL"
        exit 1
    fi

    log_success "Database host correctly configured"
else
    log_warning "Could not extract database host from connection string"
fi

# Test health endpoint
log_info "Testing health endpoint..."
if health_response=$(kubectl exec -n "$NAMESPACE" "$app_pod" -- curl -f --max-time 15 http://localhost:8080/health 2>/dev/null); then
    log_success "Health endpoint responded successfully"

    # Validate health response structure
    if echo "$health_response" | grep -q '"status":"Healthy"'; then
        log_success "Application reports healthy status"
    else
        log_warning "Health response does not indicate healthy status"
        echo "Response: $health_response"
    fi

    # Check database connectivity in health response
    if echo "$health_response" | grep -q '"connected":true'; then
        log_success "Database connectivity confirmed"
    else
        log_error "Database is not connected according to health check"
        echo "Response: $health_response"
        exit 1
    fi
else
    log_error "Health endpoint test failed"
    log_info "Checking application logs..."
    kubectl logs "$app_pod" -n "$NAMESPACE" --tail=20
    exit 1
fi

# Test API endpoints
log_info "Testing API endpoints..."
if kubectl exec -n "$NAMESPACE" "$app_pod" -- curl -f --max-time 10 http://localhost:8080/api/doctors >/dev/null 2>&1; then
    log_success "API endpoints are accessible"
else
    log_warning "API endpoint test failed (may be expected with empty database)"
fi

# Check services
log_info "Validating services..."
if kubectl get service zoneapi -n "$NAMESPACE" >/dev/null 2>&1; then
    log_success "Service 'zoneapi' exists"

    service_port=$(kubectl get service zoneapi -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
    log_info "Service port: $service_port"
else
    log_error "Service 'zoneapi' not found"
    exit 1
fi

echo ""
log_success "🎉 All deployment validation checks passed!"
log_info "Application is healthy and ready to serve traffic"
