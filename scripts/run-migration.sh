#!/bin/bash

# .NET AKS Migration Runner - Updated for efbundle approach
# Based on industry best practices from Microsoft and Azure samples
# Reference: https://docs.microsoft.com/en-us/azure/aks/kubernetes-action

set -e

# Configuration
NAMESPACE="${NAMESPACE:-zoneapi}"
TIMEOUT="${TIMEOUT:-60}"  # Reduced from 600 to 60 seconds (1 minute)
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ZoneAPI Database Migration Runner (efbundle) ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Timeout: $TIMEOUT seconds"
echo "Image Tag: $IMAGE_TAG"
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# Enhanced logging function
log_with_timestamp() {
  local level="$1"
  local message="$2"
  local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

  case $level in
  "INFO")
    echo -e "${BLUE}[$timestamp] INFO:${NC} $message"
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
    echo -e "[$timestamp] $message"
    ;;
  esac
}

# Function to monitor migration job in real-time
monitor_migration_realtime() {
  local job_name="$1"
  local timeout="$2"
  local counter=0
  local last_status=""

  log_with_timestamp "INFO" "Starting real-time monitoring of migration job: $job_name"

  while [ $counter -lt $timeout ]; do
    # Get job status - check for Complete condition with True status
    local job_complete=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
    local job_failed=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "False")
    local status=""
    
    # Determine overall status
    if [ "$job_complete" = "True" ]; then
      status="Complete"
    elif [ "$job_failed" = "True" ]; then
      status="Failed"
    else
      # Fallback to checking first condition type for other statuses
      status=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "NotFound")
    fi

    # Get pod status and count
    local pod_count=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    local succeeded_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" --field-selector=status.phase=Succeeded --no-headers 2>/dev/null | wc -l)
    local failed_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)

    # Show status if it changed
    if [ "$status" != "$last_status" ]; then
      log_with_timestamp "INFO" "Job status changed: $last_status -> $status"
      log_with_timestamp "DEBUG" "Pods - Total: $pod_count, Running: $running_pods, Succeeded: $succeeded_pods, Failed: $failed_pods"
      last_status="$status"
    fi

    case $status in
    "Complete")
      log_with_timestamp "SUCCESS" "Migration completed successfully after $counter seconds"

      # Show final logs
      echo -e "\n${GREEN}=== FINAL MIGRATION LOGS ===${NC}"
      kubectl logs -l job-name="$job_name" -n "$NAMESPACE" --tail=100 || log_with_timestamp "WARNING" "Could not retrieve final logs"

      return 0
      ;;
    "Failed")
      log_with_timestamp "ERROR" "Migration failed after $counter seconds"

      # Show detailed failure information
      echo -e "\n${RED}=== FAILURE ANALYSIS ===${NC}"
      log_with_timestamp "ERROR" "Job Description:"
      kubectl describe job "$job_name" -n "$NAMESPACE"

      log_with_timestamp "ERROR" "Failed Pod Logs:"
      local failed_pod_list=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" --field-selector=status.phase=Failed -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

      if [ -n "$failed_pod_list" ]; then
        for pod in $failed_pod_list; do
          echo -e "${RED}--- Logs for failed pod: $pod ---${NC}"
          kubectl logs "$pod" -n "$NAMESPACE" || log_with_timestamp "ERROR" "Could not retrieve logs for $pod"
          echo ""
        done
      else
        log_with_timestamp "WARNING" "No failed pods found to analyze"
      fi

      # Show recent events
      echo -e "\n${RED}=== RECENT EVENTS ===${NC}"
      kubectl get events -n "$NAMESPACE" --field-selector involvedObject.kind=Job,involvedObject.name="$job_name" --sort-by='.lastTimestamp' | tail -10

      return 1
      ;;
    "NotFound")
      log_with_timestamp "ERROR" "Migration job not found: $job_name"
      return 1
      ;;
    *)
      # Job is still running, show periodic updates
      if [ $((counter % 30)) -eq 0 ]; then # Every 30 seconds
        log_with_timestamp "INFO" "Migration in progress... (${counter}s/${timeout}s) - Status: $status"
        log_with_timestamp "DEBUG" "Pods - Running: $running_pods, Succeeded: $succeeded_pods, Failed: $failed_pods"

        # Show recent logs if pods are running
        if [ "$running_pods" -gt 0 ]; then
          echo -e "${PURPLE}--- Recent Migration Logs (last 10 lines) ---${NC}"
          kubectl logs -l job-name="$job_name" -n "$NAMESPACE" --tail=10 --since=30s 2>/dev/null || echo "No recent logs available"
          echo ""
        fi
      else
        echo -n "."
      fi

      sleep 5
      counter=$((counter + 5))
      ;;
    esac
  done

  log_with_timestamp "ERROR" "Migration timed out after ${timeout} seconds"

  # Show final state on timeout
  echo -e "\n${YELLOW}=== TIMEOUT ANALYSIS ===${NC}"
  log_with_timestamp "WARNING" "Final job status: $status"
  log_with_timestamp "WARNING" "Final pod counts - Total: $pod_count, Running: $running_pods, Succeeded: $succeeded_pods, Failed: $failed_pods"

  # Show logs from any running pods
  if [ "$running_pods" -gt 0 ]; then
    echo -e "${YELLOW}--- Logs from running pods ---${NC}"
    kubectl logs -l job-name="$job_name" -n "$NAMESPACE" --tail=50 || log_with_timestamp "WARNING" "Could not retrieve timeout logs"
  fi

  return 1
}

# Function to check if migration job exists
check_migration_job() {
  local job_name="$1"
  kubectl get job "$job_name" -n "$NAMESPACE" >/dev/null 2>&1
}

# Function to wait for migration job completion
wait_for_migration() {
  local job_name="$1"
  local timeout="$2"

  log_with_timestamp "INFO" "Waiting for migration job '$job_name' to complete (timeout: ${timeout}s)"

  # Use enhanced real-time monitoring
  monitor_migration_realtime "$job_name" "$timeout"
}

# Function to cleanup old migration jobs
cleanup_old_migrations() {
  echo -e "${BLUE}=== Cleaning up old migration jobs ===${NC}"

  # Keep only the last 3 migration jobs
  local old_jobs=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[0:-3].metadata.name}' 2>/dev/null)

  if [ -n "$old_jobs" ]; then
    echo "Deleting old migration jobs: $old_jobs"
    echo "$old_jobs" | xargs -r kubectl delete job -n "$NAMESPACE"
  else
    echo "No old migration jobs to clean up"
  fi
}

# Function to ensure database secret is updated with correct password
update_database_secret() {
  local db_password="$1"

  if [ -z "$db_password" ]; then
    log_with_timestamp "ERROR" "Database password is required to update secret"
    return 1
  fi

  log_with_timestamp "INFO" "Updating database secret with new password"

  # Delete existing secret if it exists
  kubectl delete secret zoneapi-db-secret -n "$NAMESPACE" --ignore-not-found=true

  # Create new secret with updated password
  kubectl create secret generic zoneapi-db-secret \
    --from-literal=password="$db_password" \
    -n "$NAMESPACE"

  if [ $? -eq 0 ]; then
    log_with_timestamp "SUCCESS" "Database secret updated successfully"
  else
    log_with_timestamp "ERROR" "Failed to update database secret"
    return 1
  fi
}

# Function to run migration using Helm
run_migration_with_helm() {
  log_with_timestamp "INFO" "Starting migration with Helm (efbundle approach)"

  # Get necessary values from environment or defaults
  local acr_login_server="${ACR_LOGIN_SERVER:-}"
  local database_host="${DATABASE_HOST:-}"
  local db_password="${DB_PASSWORD:-}"
  local image_tag="${IMAGE_TAG:-latest}"

  log_with_timestamp "DEBUG" "Environment Variables Received:"
  log_with_timestamp "DEBUG" "ACR_LOGIN_SERVER: ${acr_login_server:-[EMPTY]}"
  log_with_timestamp "DEBUG" "DATABASE_HOST: ${database_host:-[EMPTY]}"
  log_with_timestamp "DEBUG" "DB_PASSWORD: ${db_password:+[PROVIDED]}"
  log_with_timestamp "DEBUG" "IMAGE_TAG: ${image_tag:-[EMPTY]}"

  if [ -z "$acr_login_server" ] || [ -z "$database_host" ] || [ -z "$db_password" ]; then
    log_with_timestamp "ERROR" "Missing required environment variables"
    echo "ACR_LOGIN_SERVER: ${acr_login_server:-[MISSING]}"
    echo "DATABASE_HOST: ${database_host:-[MISSING]}"
    echo "DB_PASSWORD: ${db_password:+[PROVIDED]}"
    echo "IMAGE_TAG: ${image_tag:-[MISSING]}"
    return 1
  fi

  # Validate kubectl connectivity
  if ! kubectl cluster-info &>/dev/null; then
    log_with_timestamp "ERROR" "kubectl is not connected to any cluster"
    return 1
  fi
  log_with_timestamp "SUCCESS" "kubectl available and connected to cluster"

  log_with_timestamp "INFO" "Migration configuration validated"
  log_with_timestamp "DEBUG" "ACR Server: $acr_login_server"
  log_with_timestamp "DEBUG" "Database Host: $database_host"
  log_with_timestamp "DEBUG" "Image Tag: $image_tag"

  # Deploy migration job using Helm
  log_with_timestamp "INFO" "Deploying migration job via Helm template"

  # Construct full image path
  local full_image="${acr_login_server}/zoneapi:${image_tag}"
  log_with_timestamp "DEBUG" "Full image path: $full_image"

  # Debug Helm values being set
  log_with_timestamp "DEBUG" "Helm Values Being Set:"
  log_with_timestamp "DEBUG" "  migration.enabled=true"
  log_with_timestamp "DEBUG" "  image.repository=$acr_login_server/zoneapi"
  log_with_timestamp "DEBUG" "  image.tag=$image_tag"
  log_with_timestamp "DEBUG" "  database.host=$database_host"
  log_with_timestamp "DEBUG" "  database.password=[HIDDEN]"

  if helm template zoneapi-migration ./charts/zoneapi \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set migration.enabled=true \
    --set debug.enabled=false \
    --set image.repository="$acr_login_server/zoneapi" \
    --set image.tag="$image_tag" \
    --set database.host="$database_host" \
    --set database.password="$db_password" \
    --set database.port=5432 \
    --set database.name="zone" \
    --set database.user="postgres" \
    --set environment="Development" \
    --set image.pullPolicy="IfNotPresent" | kubectl apply -f -; then
    log_with_timestamp "SUCCESS" "Migration job template applied successfully"

    # Give Kubernetes a moment to process the job creation
    sleep 3

    # Debug: Check what was actually created immediately after
    log_with_timestamp "DEBUG" "Checking resources created immediately after template application:"
    kubectl get jobs -n "$NAMESPACE" -o wide 2>/dev/null || echo "No jobs found"
    kubectl get all -n "$NAMESPACE" -l app.kubernetes.io/component=migration 2>/dev/null || echo "No migration resources found"

    # Also check recent events to see if there are any immediate failures
    log_with_timestamp "DEBUG" "Recent events after job creation:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -5
  else
    log_with_timestamp "ERROR" "Failed to apply migration job template"
    return 1
  fi

  # Wait for job to be created and get its name
  log_with_timestamp "INFO" "Waiting for migration job to be created..."
  local retries=0
  local max_retries=12 # 1 minute with 5-second intervals
  local actual_job_name=""

  while [ $retries -lt $max_retries ]; do
    # Try multiple approaches to find the job
    actual_job_name=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")

    # If not found by label, try to find any recent migration job by name pattern
    if [ -z "$actual_job_name" ]; then
      actual_job_name=$(kubectl get jobs -n "$NAMESPACE" --no-headers 2>/dev/null | grep "migration-migration-latest" | tail -1 | awk '{print $1}' || echo "")
    fi

    # Debug: Show all jobs in namespace to see what exists
    if [ -z "$actual_job_name" ]; then
      log_with_timestamp "DEBUG" "All jobs in namespace:"
      kubectl get jobs -n "$NAMESPACE" -o name 2>/dev/null || echo "No jobs found"

      log_with_timestamp "DEBUG" "Jobs with migration component label:"
      kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o name 2>/dev/null || echo "No jobs with migration label found"
    fi

    if [ -n "$actual_job_name" ]; then
      log_with_timestamp "SUCCESS" "Migration job created: $actual_job_name"
      break
    fi

    log_with_timestamp "DEBUG" "Waiting for job creation... (attempt $((retries + 1))/$max_retries)"
    sleep 5
    retries=$((retries + 1))
  done

  if [ -z "$actual_job_name" ]; then
    log_with_timestamp "ERROR" "Failed to create or find migration job after $max_retries attempts"

    # Show debugging information
    echo -e "\n${RED}=== JOB CREATION DEBUGGING ===${NC}"
    log_with_timestamp "DEBUG" "All jobs in namespace:"
    kubectl get jobs -n "$NAMESPACE" -o wide

    log_with_timestamp "DEBUG" "Recent events:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10

    return 1
  fi

  # Wait for migration completion with enhanced monitoring
  wait_for_migration "$actual_job_name" "$TIMEOUT"
}

# Function to verify migration was successful
verify_migration() {
  echo -e "${BLUE}=== Verifying Migration Success ===${NC}"

  # Get the latest migration job
  local latest_job=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)

  if [ -n "$latest_job" ]; then
    echo -e "${YELLOW}Migration Job Details:${NC}"
    kubectl describe job "$latest_job" -n "$NAMESPACE"

    echo -e "${YELLOW}Migration Logs:${NC}"
    kubectl logs -l job-name="$latest_job" -n "$NAMESPACE" --tail=100
  fi

  echo -e "${GREEN}✅ Migration verification completed${NC}"
}

# Main execution
main() {
  echo -e "${BLUE}🚀 Starting efbundle migration process...${NC}"

  # Run migration
  if run_migration_with_helm; then
    verify_migration
    cleanup_old_migrations
    echo -e "${GREEN}🎉 Migration process completed successfully!${NC}"
    return 0
  else
    echo -e "${RED}💥 Migration process failed!${NC}"
    verify_migration # Still show details for debugging
    return 1
  fi
}

# Execute main function
main "$@"
