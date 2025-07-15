#!/bin/bash

# .NET AKS Migration Runner - Updated for efbundle approach
# Based on industry best practices from Microsoft and Azure samples
# Reference: https://docs.microsoft.com/en-us/azure/aks/kubernetes-action

set -e

# Configuration
NAMESPACE="${NAMESPACE:-zoneapi}"
TIMEOUT="${TIMEOUT:-600}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ZoneAPI Database Migration Runner (efbundle) ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Timeout: $TIMEOUT seconds"
echo "Image Tag: $IMAGE_TAG"
echo ""

# Function to check if migration job exists
check_migration_job() {
  local job_name="$1"
  kubectl get job "$job_name" -n "$NAMESPACE" >/dev/null 2>&1
}

# Function to wait for migration job completion
wait_for_migration() {
  local job_name="$1"
  local timeout="$2"
  local counter=0

  echo -e "${BLUE}Waiting for migration job to complete...${NC}"

  while [ $counter -lt $timeout ]; do
    local status=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "NotFound")

    case $status in
    "Complete")
      echo -e "${GREEN}✅ Migration completed successfully${NC}"
      return 0
      ;;
    "Failed")
      echo -e "${RED}❌ Migration failed${NC}"
      echo -e "${YELLOW}Job Status:${NC}"
      kubectl describe job "$job_name" -n "$NAMESPACE"
      echo -e "${YELLOW}Pod Logs:${NC}"
      kubectl logs -l job-name="$job_name" -n "$NAMESPACE" --tail=50
      return 1
      ;;
    "NotFound")
      echo -e "${RED}❌ Migration job not found${NC}"
      return 1
      ;;
    *)
      echo -n "."
      sleep 5
      counter=$((counter + 5))
      ;;
    esac
  done

  echo -e "${RED}❌ Migration timed out after ${timeout} seconds${NC}"
  return 1
}

# Function to run migration using Helm
run_migration_with_helm() {
  echo -e "${BLUE}=== Running Migration with Helm (efbundle approach) ===${NC}"

  # Generate unique migration job name with timestamp
  local timestamp=$(date +%s)
  local migration_job_name="zoneapi-migration-${timestamp}"

  # Get necessary values from environment or defaults
  local acr_login_server="${ACR_LOGIN_SERVER:-}"
  local database_host="${DATABASE_HOST:-}"
  local db_password="${DB_PASSWORD:-}"

  if [ -z "$acr_login_server" ] || [ -z "$database_host" ] || [ -z "$db_password" ]; then
    echo -e "${RED}❌ Missing required environment variables:${NC}"
    echo "ACR_LOGIN_SERVER: $acr_login_server"
    echo "DATABASE_HOST: $database_host"
    echo "DB_PASSWORD: [REDACTED]"
    return 1
  fi

  # Deploy migration job using Helm
  helm template zoneapi-migration ./charts/zoneapi \
    --set migration.enabled=true \
    --set image.repository="$acr_login_server/zoneapi" \
    --set image.tag="$IMAGE_TAG" \
    --set database.host="$database_host" \
    --set database.password="$db_password" \
    --include-crds \
    --show-only templates/migration-job.yaml |
    kubectl apply -f - -n "$NAMESPACE"

  # Extract job name from the applied template
  local actual_job_name=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)

  if [ -z "$actual_job_name" ]; then
    echo -e "${RED}❌ Failed to create migration job${NC}"
    return 1
  fi

  echo -e "${GREEN}✅ Migration job created: $actual_job_name${NC}"

  # Wait for migration completion
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
