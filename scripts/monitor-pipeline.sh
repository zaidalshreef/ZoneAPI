#!/bin/bash

# Pipeline Monitoring Script
# Monitor ZoneAPI CI/CD Pipeline Progress with Enhanced Real-time Capabilities

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-zoneapi}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-10}"   # seconds
MAX_MONITOR_TIME="${MAX_MONITOR_TIME:-1800}" # 30 minutes

echo -e "${BLUE}=== ZoneAPI CI/CD Pipeline Monitor (Enhanced) ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Monitor Interval: ${MONITOR_INTERVAL}s"
echo "Max Monitor Time: ${MAX_MONITOR_TIME}s"
echo "Start Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# Enhanced logging function
log_monitor() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

    case $level in
    "INFO")
        echo -e "${CYAN}[$timestamp] MONITOR:${NC} $message"
        ;;
    "SUCCESS")
        echo -e "${GREEN}[$timestamp] SUCCESS:${NC} $message"
        ;;
    "WARNING")
        echo -e "${YELLOW}[$timestamp] WARNING:${NC} $message"
        ;;
    "ERROR")
        echo -e "${RED}[$timestamp] ERROR:${NC} $message"
        ;;
    "DEBUG")
        echo -e "${PURPLE}[$timestamp] DEBUG:${NC} $message"
        ;;
    *)
        echo -e "${CYAN}[$timestamp]${NC} $message"
        ;;
    esac
}

# Check if we have kubectl and can connect to cluster
check_kubectl() {
    if command -v kubectl &>/dev/null; then
        if kubectl cluster-info &>/dev/null; then
            log_monitor "SUCCESS" "kubectl available and connected to cluster"
            return 0
        else
            log_monitor "ERROR" "kubectl available but not connected to cluster"
            return 1
        fi
    else
        log_monitor "WARNING" "kubectl not available - cannot monitor cluster directly"
        return 1
    fi
}

# Get comprehensive cluster status
get_cluster_status() {
    log_monitor "INFO" "=== CLUSTER STATUS ==="

    # Cluster info
    echo -e "${PURPLE}Cluster Information:${NC}"
    kubectl cluster-info --request-timeout=10s 2>/dev/null || log_monitor "WARNING" "Could not get cluster info"

    # Node status
    echo -e "\n${PURPLE}Node Status:${NC}"
    kubectl get nodes -o wide --request-timeout=10s 2>/dev/null || log_monitor "WARNING" "Could not get node status"

    # Namespace status
    echo -e "\n${PURPLE}Namespace Status:${NC}"
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_monitor "SUCCESS" "Namespace '$NAMESPACE' exists"
    else
        log_monitor "WARNING" "Namespace '$NAMESPACE' does not exist"
        return 1
    fi
}

# Monitor migration job with detailed tracking
monitor_migration_detailed() {
    log_monitor "INFO" "=== MIGRATION JOB MONITORING ==="

    # Get all migration jobs
    local migration_jobs=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration --no-headers 2>/dev/null | awk '{print $1}' || echo "")

    if [ -z "$migration_jobs" ]; then
        log_monitor "INFO" "No migration jobs found (yet)"
        return 0
    fi

    echo -e "${GREEN}Found migration jobs:${NC}"
    for job in $migration_jobs; do
        local job_status=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
        local job_age=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "Unknown")

        echo -e "  📋 Job: ${BLUE}$job${NC} | Status: ${GREEN}$job_status${NC} | Created: $job_age"

        # Get pod details for this job
        local job_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job" --no-headers 2>/dev/null | awk '{print $1 " " $3}' || echo "")
        if [ -n "$job_pods" ]; then
            echo "$job_pods" | while read pod_name pod_status; do
                if [ -n "$pod_name" ]; then
                    echo -e "    🐳 Pod: ${PURPLE}$pod_name${NC} | Status: ${YELLOW}$pod_status${NC}"
                fi
            done
        fi

        # Show recent logs if job is running or failed
        if [ "$job_status" = "Failed" ]; then
            echo -e "    ${RED}📋 Recent failure logs:${NC}"
            kubectl logs -l job-name="$job" -n "$NAMESPACE" --tail=5 2>/dev/null | sed 's/^/      /' || echo "      No logs available"
        elif kubectl get pods -n "$NAMESPACE" -l job-name="$job" --field-selector=status.phase=Running &>/dev/null; then
            echo -e "    ${CYAN}📋 Recent activity logs:${NC}"
            kubectl logs -l job-name="$job" -n "$NAMESPACE" --tail=3 --since=60s 2>/dev/null | sed 's/^/      /' || echo "      No recent logs"
        fi
        echo ""
    done
}

# Monitor application pods
monitor_application_detailed() {
    log_monitor "INFO" "=== APPLICATION PODS MONITORING ==="

    local app_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi --no-headers 2>/dev/null || echo "")

    if [ -z "$app_pods" ]; then
        log_monitor "INFO" "No application pods found (yet)"
        return 0
    fi

    echo -e "${GREEN}Application Pods Status:${NC}"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi -o wide 2>/dev/null || log_monitor "WARNING" "Could not get pod details"

    # Check pod health
    echo -e "\n${PURPLE}Pod Health Details:${NC}"
    local pod_names=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    for pod in $pod_names; do
        if [ -n "$pod" ]; then
            local pod_status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            local ready_status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

            echo -e "  🐳 Pod: ${BLUE}$pod${NC}"
            echo -e "     Status: ${GREEN}$pod_status${NC} | Ready: ${YELLOW}$ready_status${NC}"

            # Show recent logs for running pods
            if [ "$pod_status" = "Running" ]; then
                echo -e "     ${CYAN}Recent logs:${NC}"
                kubectl logs "$pod" -n "$NAMESPACE" --tail=3 --since=60s 2>/dev/null | sed 's/^/       /' || echo "       No recent logs"
            fi
            echo ""
        fi
    done
}

# Monitor services and endpoints
monitor_services() {
    log_monitor "INFO" "=== SERVICES & ENDPOINTS MONITORING ==="

    echo -e "${PURPLE}Services:${NC}"
    kubectl get services -n "$NAMESPACE" -o wide 2>/dev/null || log_monitor "WARNING" "Could not get services"

    echo -e "\n${PURPLE}Endpoints:${NC}"
    kubectl get endpoints -n "$NAMESPACE" 2>/dev/null || log_monitor "WARNING" "Could not get endpoints"
}

# Monitor recent events
monitor_events() {
    log_monitor "INFO" "=== RECENT EVENTS ==="

    echo -e "${PURPLE}Last 15 events in namespace $NAMESPACE:${NC}"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' --request-timeout=10s 2>/dev/null | tail -15 || log_monitor "WARNING" "Could not get events"
}

# Monitor resource usage
monitor_resources() {
    log_monitor "INFO" "=== RESOURCE MONITORING ==="

    # Check if metrics-server is available
    if kubectl top nodes &>/dev/null; then
        echo -e "${PURPLE}Node Resource Usage:${NC}"
        kubectl top nodes 2>/dev/null || log_monitor "WARNING" "Could not get node metrics"

        echo -e "\n${PURPLE}Pod Resource Usage:${NC}"
        kubectl top pods -n "$NAMESPACE" 2>/dev/null || log_monitor "WARNING" "Could not get pod metrics"
    else
        log_monitor "INFO" "Metrics server not available - skipping resource monitoring"
    fi
}

# Main monitoring loop
run_monitoring_loop() {
    local start_time=$(date +%s)
    local iteration=0

    log_monitor "INFO" "Starting continuous monitoring loop..."

    while true; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        iteration=$((iteration + 1))

        # Check if we've exceeded max monitoring time
        if [ $elapsed_time -gt $MAX_MONITOR_TIME ]; then
            log_monitor "WARNING" "Maximum monitoring time ($MAX_MONITOR_TIME seconds) reached"
            break
        fi

        echo -e "\n${CYAN}=================== MONITORING ITERATION $iteration (${elapsed_time}s elapsed) ===================${NC}"

        # Run all monitoring functions
        monitor_migration_detailed
        monitor_application_detailed
        monitor_services
        monitor_events

        # Resource monitoring every 5th iteration to reduce noise
        if [ $((iteration % 5)) -eq 0 ]; then
            monitor_resources
        fi

        echo -e "\n${CYAN}Next check in ${MONITOR_INTERVAL} seconds...${NC}"
        sleep $MONITOR_INTERVAL
    done

    log_monitor "INFO" "Monitoring loop completed after $iteration iterations"
}

# Single status check function
run_single_check() {
    log_monitor "INFO" "Running single status check..."

    get_cluster_status
    monitor_migration_detailed
    monitor_application_detailed
    monitor_services
    monitor_events
    monitor_resources

    log_monitor "INFO" "Single status check completed"
}

# Main execution
main() {
    if ! check_kubectl; then
        log_monitor "ERROR" "Cannot proceed without kubectl access"
        exit 1
    fi

    # Check if we should run continuously or just once
    if [ "${CONTINUOUS_MONITORING:-false}" = "true" ]; then
        run_monitoring_loop
    else
        run_single_check
    fi
}

# Handle script interruption
trap 'log_monitor "INFO" "Monitoring interrupted by user"; exit 0' INT TERM

# Execute main function
main "$@"
