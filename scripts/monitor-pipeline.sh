#!/bin/bash

# Pipeline Monitoring Script
# Monitor ZoneAPI CI/CD Pipeline Progress

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ZoneAPI CI/CD Pipeline Monitor ===${NC}"
echo ""

# Check if we have kubectl and can connect to cluster
check_kubectl() {
    if command -v kubectl &>/dev/null; then
        echo -e "${GREEN}✅ kubectl available${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  kubectl not available - cannot monitor cluster directly${NC}"
        return 1
    fi
}

# Monitor migration job if kubectl is available
monitor_migration() {
    if check_kubectl; then
        echo -e "${PURPLE}=== Migration Job Status ===${NC}"
        kubectl get jobs -n zoneapi -l app.kubernetes.io/component=migration --no-headers 2>/dev/null | while read job; do
            if [ -n "$job" ]; then
                echo -e "${GREEN}Migration job found: $job${NC}"
            fi
        done || echo -e "${YELLOW}No migration jobs found (yet)${NC}"
        echo ""
    fi
}

# Monitor application pods
monitor_application() {
    if check_kubectl; then
        echo -e "${PURPLE}=== Application Pods Status ===${NC}"
        kubectl get pods -n zoneapi --no-headers 2>/dev/null | while read pod; do
            if [ -n "$pod" ]; then
                echo -e "${GREEN}Pod: $pod${NC}"
            fi
        done || echo -e "${YELLOW}No application pods found (yet)${NC}"
        echo ""
    fi
}

# Main monitoring function
main() {
    echo -e "${BLUE}🔄 Monitoring pipeline...${NC}"
    echo ""

    echo -e "${PURPLE}=== Pipeline Jobs (GitHub Actions) ===${NC}"
    echo "1. 🏗️  Build and Test"
    echo "2. 🏗️  Infrastructure Deployment"
    echo "3. 🐳 Docker Build & Push"
    echo "4. 📊 Database Migration (NEW - Standalone)"
    echo "5. 🚀 Application Deployment (POST-migration)"
    echo ""

    echo -e "${BLUE}🔗 Monitor at: https://github.com/zaidalshreef/ZoneAPI/actions${NC}"
    echo ""

    # Monitor Kubernetes resources if available
    monitor_migration
    monitor_application

    echo -e "${GREEN}=== Industry Best Practices Implemented ===${NC}"
    echo "✅ Separated migration from deployment (prevents blocking)"
    echo "✅ Using EF Core migration bundles (Microsoft recommended)"
    echo "✅ Removed problematic pre-install hooks"
    echo "✅ Standalone migration job with proper timeouts"
    echo "✅ Two-phase deployment: Migration → Application"
    echo "✅ Resource-optimized Helm charts"
    echo ""

    echo -e "${YELLOW}💡 Key Benefits:${NC}"
    echo "• No more pre-install hook timeouts"
    echo "• Faster failure detection"
    echo "• Independent migration troubleshooting"
    echo "• Industry-standard deployment pattern"
    echo "• Better resource utilization"
}

# Run with watch if requested
if [ "$1" == "--watch" ]; then
    while true; do
        clear
        main
        echo ""
        echo -e "${BLUE}Refreshing in 30 seconds... (Ctrl+C to stop)${NC}"
        sleep 30
    done
else
    main
fi
