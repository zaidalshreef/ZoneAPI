#!/bin/bash

# ZoneAPI Application Status Checker
# Shows current deployment status and external access information

set -e

# Configuration
NAMESPACE="${NAMESPACE:-zoneapi}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ZoneAPI Application Status ===${NC}"
echo "Namespace: $NAMESPACE"
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
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

# Check pods
echo -e "${PURPLE}=== Pod Status ===${NC}"
kubectl get pods -n "$NAMESPACE" -o wide

# Check services
echo ""
echo -e "${PURPLE}=== Service Status ===${NC}"
kubectl get services -n "$NAMESPACE" -o wide

# Get external IP
external_ip=$(kubectl get service zoneapi -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
service_type=$(kubectl get service zoneapi -n "$NAMESPACE" -o jsonpath='{.spec.type}' 2>/dev/null || echo "Unknown")

echo ""
echo -e "${PURPLE}=== External Access Information ===${NC}"
echo "Service Type: $service_type"

if [ -n "$external_ip" ]; then
    log_success "External IP: $external_ip"

    echo ""
    echo -e "${PURPLE}=== Testing Endpoints ===${NC}"

    # Test health endpoint
    echo -n "Health Check: "
    if health_response=$(curl -s --max-time 10 "http://$external_ip:8080/health" 2>/dev/null); then
        if echo "$health_response" | grep -q '"status":"Healthy"'; then
            log_success "✅ Healthy"

            # Check database connectivity
            if echo "$health_response" | grep -q '"connected":true'; then
                log_success "✅ Database Connected"
            else
                log_warning "⚠️ Database Issue"
            fi
        else
            log_warning "⚠️ Unhealthy Response"
        fi
    else
        log_error "❌ Health endpoint not accessible"
    fi

    # Test API endpoints
    echo -n "Doctors API: "
    if curl -s --max-time 5 "http://$external_ip:8080/api/doctors" >/dev/null 2>&1; then
        log_success "✅ Accessible"
    else
        log_error "❌ Not accessible"
    fi

    echo -n "Patients API: "
    if curl -s --max-time 5 "http://$external_ip:8080/api/patients" >/dev/null 2>&1; then
        log_success "✅ Accessible"
    else
        log_error "❌ Not accessible"
    fi

    echo ""
    echo -e "${GREEN}=== 🌐 External Access URLs ===${NC}"
    echo "Health Check: http://$external_ip:8080/health"
    echo "Doctors API:  http://$external_ip:8080/api/doctors"
    echo "Patients API: http://$external_ip:8080/api/patients"
    echo "Appointments: http://$external_ip:8080/api/appointments"

elif [ "$service_type" = "LoadBalancer" ]; then
    log_warning "LoadBalancer IP is still provisioning..."
    echo "Please wait a moment and run this script again."

elif [ "$service_type" = "ClusterIP" ]; then
    log_info "Service is ClusterIP - only accessible within cluster"
    echo "To enable external access, run:"
    echo "kubectl patch service zoneapi -n $NAMESPACE -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"

else
    log_error "Unknown service configuration"
fi

# Check ingress if exists
ingress_count=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$ingress_count" -gt 0 ]; then
    echo ""
    echo -e "${PURPLE}=== Ingress Status ===${NC}"
    kubectl get ingress -n "$NAMESPACE" -o wide
fi

echo ""
log_success "Status check complete!"
