#!/bin/bash

# ZoneAPI Migration Status Debug Script
# Comprehensive analysis of migration status and database connectivity
# Usage: ./debug-migration-status.sh [namespace]

set -e

# Configuration
NAMESPACE="${1:-zoneapi}"
DB_SECRET_NAME="zoneapi-db-secret"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}${BLUE}=== ZoneAPI Migration Status Debug Tool ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# Enhanced logging function
debug_log() {
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
    "DEBUG")
        echo -e "${PURPLE}[$timestamp] 🔍 DEBUG:${NC} $message"
        ;;
    "SECTION")
        echo -e "\n${BOLD}${BLUE}=== $message ===${NC}"
        ;;
    *)
        echo -e "[$timestamp] $message"
        ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    debug_log "SECTION" "CHECKING PREREQUISITES"

    # Check kubectl
    if command -v kubectl &>/dev/null; then
        debug_log "SUCCESS" "kubectl is installed"

        if kubectl cluster-info &>/dev/null; then
            debug_log "SUCCESS" "kubectl is connected to cluster"
        else
            debug_log "ERROR" "kubectl is not connected to cluster"
            echo "Run: az aks get-credentials --resource-group <resource-group> --name <cluster-name>"
            exit 1
        fi
    else
        debug_log "ERROR" "kubectl is not installed"
        exit 1
    fi

    # Check namespace
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        debug_log "SUCCESS" "Namespace '$NAMESPACE' exists"
    else
        debug_log "ERROR" "Namespace '$NAMESPACE' does not exist"
        echo "Available namespaces:"
        kubectl get namespaces --no-headers | awk '{print "  - " $1}'
        exit 1
    fi
}

# Check database secrets and connectivity
check_database_connectivity() {
    debug_log "SECTION" "DATABASE CONNECTIVITY CHECK"

    # Check if secret exists
    if kubectl get secret "$DB_SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
        debug_log "SUCCESS" "Database secret '$DB_SECRET_NAME' exists"

        # Get database password from secret
        local db_password=$(kubectl get secret "$DB_SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")

        if [ -n "$db_password" ]; then
            debug_log "SUCCESS" "Database password retrieved from secret"

            # Try to get database host from environment or deployment
            local db_host=""

            # Check if there are any deployments with database connection string
            local app_deployment=$(kubectl get deployments -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

            if [ -n "$app_deployment" ]; then
                db_host=$(kubectl get deployment "$app_deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ConnectionStrings__PostgreSQLConnection")].value}' 2>/dev/null | grep -o 'Host=[^;]*' | cut -d'=' -f2 || echo "")
            fi

            if [ -z "$db_host" ]; then
                debug_log "WARNING" "Could not extract database host from deployment"
                debug_log "INFO" "Attempting to find database host from ConfigMaps or other sources..."

                # Try to find from migration jobs
                local migration_job=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                if [ -n "$migration_job" ]; then
                    db_host=$(kubectl get job "$migration_job" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].command}' 2>/dev/null | grep -o 'Host=[^;]*' | cut -d'=' -f2 || echo "")
                fi
            fi

            if [ -n "$db_host" ]; then
                debug_log "SUCCESS" "Database host found: $db_host"

                # Test database connectivity from within cluster
                debug_log "INFO" "Testing database connectivity from within cluster..."

                if test_db_connection_from_cluster "$db_host" "$db_password"; then
                    debug_log "SUCCESS" "Database connectivity test passed"
                else
                    debug_log "ERROR" "Database connectivity test failed"
                fi
            else
                debug_log "WARNING" "Could not determine database host"
            fi
        else
            debug_log "ERROR" "Could not retrieve database password from secret"
        fi
    else
        debug_log "ERROR" "Database secret '$DB_SECRET_NAME' not found"
        echo "Available secrets in namespace:"
        kubectl get secrets -n "$NAMESPACE" --no-headers | awk '{print "  - " $1}'
    fi
}

# Test database connection from cluster
test_db_connection_from_cluster() {
    local db_host="$1"
    local db_password="$2"

    debug_log "INFO" "Running database connection test pod..."

    local test_result=$(kubectl run db-connectivity-test-$(date +%s) \
        --image=postgres:15-alpine \
        --rm -i --restart=Never \
        --namespace="$NAMESPACE" \
        --timeout=60s \
        --overrides="{
      \"spec\": {
        \"containers\": [{
          \"name\": \"db-test\",
          \"image\": \"postgres:15-alpine\",
          \"env\": [{
            \"name\": \"PGPASSWORD\",
            \"value\": \"$db_password\"
          }],
          \"command\": [\"psql\"],
          \"args\": [
            \"-h\", \"$db_host\",
            \"-U\", \"postgres\",
            \"-d\", \"zone\",
            \"-c\", \"SELECT 'Connection successful' as status, version(), current_database(), current_user;\"
          ]
        }]
      }
    }" 2>&1) || true

    if echo "$test_result" | grep -q "Connection successful"; then
        debug_log "SUCCESS" "Database connection test successful"
        echo "$test_result" | grep -E "(status|version|current_)" | sed 's/^/    /'
        return 0
    else
        debug_log "ERROR" "Database connection test failed"
        echo "$test_result" | tail -10 | sed 's/^/    /'
        return 1
    fi
}

# Analyze migration jobs
analyze_migration_jobs() {
    debug_log "SECTION" "MIGRATION JOBS ANALYSIS"

    local migration_jobs=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration --no-headers 2>/dev/null | awk '{print $1}' || echo "")

    if [ -z "$migration_jobs" ]; then
        debug_log "WARNING" "No migration jobs found"
        return 0
    fi

    debug_log "INFO" "Found $(echo "$migration_jobs" | wc -w) migration job(s)"

    for job in $migration_jobs; do
        echo ""
        debug_log "INFO" "Analyzing job: $job"

        # Get job details
        local job_status=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
        local job_reason=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
        local job_message=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "No message")
        local creation_time=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "Unknown")
        local completions=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        local failures=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")

        echo -e "    ${PURPLE}Job Details:${NC}"
        echo -e "      Status: ${GREEN}$job_status${NC}"
        echo -e "      Reason: $job_reason"
        echo -e "      Message: $job_message"
        echo -e "      Created: $creation_time"
        echo -e "      Completions: $completions | Failures: $failures"

        # Get pod details for this job
        local job_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job" --no-headers 2>/dev/null || echo "")

        if [ -n "$job_pods" ]; then
            echo -e "\n    ${PURPLE}Associated Pods:${NC}"
            echo "$job_pods" | while read pod_name pod_ready pod_status pod_restarts pod_age; do
                if [ -n "$pod_name" ]; then
                    echo -e "      🐳 Pod: ${BLUE}$pod_name${NC} | Status: ${YELLOW}$pod_status${NC} | Ready: $pod_ready | Restarts: $pod_restarts | Age: $pod_age"

                    # Show recent logs for this pod
                    echo -e "      ${CYAN}Recent logs (last 10 lines):${NC}"
                    kubectl logs "$pod_name" -n "$NAMESPACE" --tail=10 2>/dev/null | sed 's/^/        /' || echo "        No logs available"
                fi
            done
        else
            debug_log "WARNING" "No pods found for job $job"
        fi

        # Show recent events for this job
        echo -e "\n    ${PURPLE}Recent Events:${NC}"
        kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$job",involvedObject.kind=Job --sort-by='.lastTimestamp' 2>/dev/null | tail -5 | sed 's/^/      /' || echo "      No events found"
    done
}

# Check database state
check_database_state() {
    debug_log "SECTION" "DATABASE STATE CHECK"

    # Get database connection details
    local db_host=""
    local db_password=$(kubectl get secret "$DB_SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

    # Try to get DB host from deployment
    local app_deployment=$(kubectl get deployments -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$app_deployment" ]; then
        db_host=$(kubectl get deployment "$app_deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ConnectionStrings__PostgreSQLConnection")].value}' 2>/dev/null | grep -o 'Host=[^;]*' | cut -d'=' -f2 || echo "")
    fi

    if [ -n "$db_host" ] && [ -n "$db_password" ]; then
        debug_log "INFO" "Checking database schema and migration history..."

        local db_state=$(kubectl run db-state-check-$(date +%s) \
            --image=postgres:15-alpine \
            --rm -i --restart=Never \
            --namespace="$NAMESPACE" \
            --timeout=60s \
            --overrides="{
        \"spec\": {
          \"containers\": [{
            \"name\": \"db-state\",
            \"image\": \"postgres:15-alpine\",
            \"env\": [{
              \"name\": \"PGPASSWORD\",
              \"value\": \"$db_password\"
            }],
            \"command\": [\"psql\"],
            \"args\": [
              \"-h\", \"$db_host\",
              \"-U\", \"postgres\",
              \"-d\", \"zone\",
              \"-c\", \"\\\\dt; SELECT 'MIGRATION_HISTORY:' as marker; SELECT COUNT(*) as total_migrations FROM __EFMigrationsHistory; SELECT migration_id, product_version FROM __EFMigrationsHistory ORDER BY migration_id;\"
            ]
          }]
        }
      }" 2>&1) || true

        if echo "$db_state" | grep -q "MIGRATION_HISTORY:"; then
            debug_log "SUCCESS" "Database schema information retrieved"
            echo "$db_state" | sed 's/^/    /'
        else
            debug_log "WARNING" "Could not retrieve database schema information"
            echo "$db_state" | tail -10 | sed 's/^/    /'
        fi
    else
        debug_log "WARNING" "Could not determine database connection details for state check"
    fi
}

# Analyze application pods
analyze_application_pods() {
    debug_log "SECTION" "APPLICATION PODS ANALYSIS"

    local app_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi --no-headers 2>/dev/null || echo "")

    if [ -z "$app_pods" ]; then
        debug_log "WARNING" "No application pods found"
        return 0
    fi

    debug_log "INFO" "Found application pods"

    echo "$app_pods" | while read pod_name pod_ready pod_status pod_restarts pod_age; do
        if [ -n "$pod_name" ]; then
            echo ""
            debug_log "INFO" "Analyzing pod: $pod_name"

            # Get detailed pod information
            local pod_phase=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            local ready_condition=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            local restart_policy=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.spec.restartPolicy}' 2>/dev/null || echo "Unknown")

            echo -e "    ${PURPLE}Pod Details:${NC}"
            echo -e "      Phase: ${GREEN}$pod_phase${NC}"
            echo -e "      Ready: $ready_condition"
            echo -e "      Restarts: $pod_restarts"
            echo -e "      Restart Policy: $restart_policy"
            echo -e "      Age: $pod_age"

            # Check for any issues
            echo -e "\n    ${PURPLE}Pod Events:${NC}"
            kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$pod_name" --sort-by='.lastTimestamp' 2>/dev/null | tail -5 | sed 's/^/      /' || echo "      No events found"

            # Show recent logs
            echo -e "\n    ${PURPLE}Recent Logs (last 15 lines):${NC}"
            kubectl logs "$pod_name" -n "$NAMESPACE" --tail=15 2>/dev/null | sed 's/^/      /' || echo "      No logs available"
        fi
    done
}

# Show services and ingress
show_services_and_ingress() {
    debug_log "SECTION" "SERVICES AND INGRESS"

    echo -e "${PURPLE}Services:${NC}"
    kubectl get services -n "$NAMESPACE" -o wide 2>/dev/null | sed 's/^/  /' || debug_log "WARNING" "No services found"

    echo -e "\n${PURPLE}Ingress:${NC}"
    kubectl get ingress -n "$NAMESPACE" -o wide 2>/dev/null | sed 's/^/  /' || debug_log "INFO" "No ingress found"

    echo -e "\n${PURPLE}Endpoints:${NC}"
    kubectl get endpoints -n "$NAMESPACE" 2>/dev/null | sed 's/^/  /' || debug_log "WARNING" "No endpoints found"
}

# Summary and recommendations
show_summary_and_recommendations() {
    debug_log "SECTION" "SUMMARY AND RECOMMENDATIONS"

    # Count resources
    local migration_jobs_count=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration --no-headers 2>/dev/null | wc -l || echo "0")
    local completed_migrations=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o jsonpath='{.items[?(@.status.conditions[0].type=="Complete")].metadata.name}' 2>/dev/null | wc -w || echo "0")
    local failed_migrations=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o jsonpath='{.items[?(@.status.conditions[0].type=="Failed")].metadata.name}' 2>/dev/null | wc -w || echo "0")
    local app_pods_count=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi --no-headers 2>/dev/null | wc -l || echo "0")
    local running_app_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")

    echo -e "${CYAN}Resource Summary:${NC}"
    echo -e "  📊 Migration Jobs: $migration_jobs_count (Completed: $completed_migrations, Failed: $failed_migrations)"
    echo -e "  🐳 Application Pods: $app_pods_count (Running: $running_app_pods)"

    echo -e "\n${YELLOW}Recommendations:${NC}"

    if [ "$failed_migrations" -gt 0 ]; then
        echo -e "  ❌ You have failed migration jobs. Check the logs above for errors."
        echo -e "     Consider cleaning up failed jobs: kubectl delete job -n $NAMESPACE -l app.kubernetes.io/component=migration"
    fi

    if [ "$completed_migrations" -eq 0 ] && [ "$migration_jobs_count" -eq 0 ]; then
        echo -e "  ⚠️  No migration jobs found. Migration may not have been triggered yet."
        echo -e "     Check your CI/CD pipeline logs."
    fi

    if [ "$running_app_pods" -eq 0 ]; then
        echo -e "  ⚠️  No running application pods found."
        echo -e "     Check if the application deployment was successful."
    fi

    echo -e "\n${BLUE}Useful Commands:${NC}"
    echo -e "  📋 Watch migration jobs: kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/component=migration -w"
    echo -e "  📋 Watch pods: kubectl get pods -n $NAMESPACE -w"
    echo -e "  📋 Follow migration logs: kubectl logs -f -l job-name=<job-name> -n $NAMESPACE"
    echo -e "  📋 Describe failed pod: kubectl describe pod <pod-name> -n $NAMESPACE"
}

# Main execution
main() {
    check_prerequisites
    check_database_connectivity
    analyze_migration_jobs
    check_database_state
    analyze_application_pods
    show_services_and_ingress
    show_summary_and_recommendations

    echo ""
    debug_log "SUCCESS" "Debug analysis completed"
}

# Execute main function
main "$@"
