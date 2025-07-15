#!/bin/bash

# .NET AKS Migration Runner
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

echo -e "${BLUE}=== ZoneAPI Database Migration Runner ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Timeout: $TIMEOUT seconds"
echo "Image Tag: $IMAGE_TAG"
echo ""

# Function to check if migration job exists
check_migration_job() {
    local job_name="$1"
    kubectl get job "$job_name" -n "$NAMESPACE" >/dev/null 2>&1
}

# Function to wait for job completion
wait_for_job() {
    local job_name="$1"
    local timeout="$2"

    echo -e "${YELLOW}⏳ Waiting for migration job to complete (timeout: ${timeout}s)...${NC}"

    if kubectl wait --for=condition=complete job/"$job_name" -n "$NAMESPACE" --timeout="${timeout}s"; then
        echo -e "${GREEN}✅ Migration job completed successfully${NC}"
        return 0
    else
        echo -e "${RED}❌ Migration job failed or timed out${NC}"
        return 1
    fi
}

# Function to get job logs
get_job_logs() {
    local job_name="$1"
    echo -e "${BLUE}📋 Migration job logs:${NC}"
    kubectl logs -l job-name="$job_name" -n "$NAMESPACE" --tail=100
}

# Function to cleanup old migration jobs
cleanup_old_jobs() {
    echo -e "${YELLOW}🧹 Cleaning up old migration jobs...${NC}"
    kubectl delete jobs -l app.kubernetes.io/component=migration -n "$NAMESPACE" --ignore-not-found=true
}

# Function to run migration
run_migration() {
    local image_tag="$1"
    local job_name="zoneapi-migration-$(echo "$image_tag" | tr '.:' '-')"

    echo -e "${BLUE}🚀 Starting database migration...${NC}"
    echo "Job name: $job_name"

    # Create migration job manifest
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $job_name
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: zoneapi
    app.kubernetes.io/component: migration
    app.kubernetes.io/version: $image_tag
spec:
  backoffLimit: 3
  activeDeadlineSeconds: $TIMEOUT
  template:
    metadata:
      labels:
        app.kubernetes.io/name: zoneapi
        app.kubernetes.io/component: migration
    spec:
      restartPolicy: Never
      containers:
      - name: migration
        image: \${ACR_LOGIN_SERVER}/zoneapi:$image_tag
        command: ["./efbundle"]
        args:
        - "--connection"
        - "Host=\${DATABASE_HOST};Port=5432;Database=zone;Username=postgres;Password=\${DB_PASSWORD};CommandTimeout=300;Timeout=60;"
        - "--verbose"
        env:
        - name: ASPNETCORE_ENVIRONMENT
          value: "Development"
        - name: DOTNET_BUNDLE_EXTRACT_BASE_DIR
          value: "/tmp"
        - name: DATABASE_HOST
          value: "\${DATABASE_HOST}"
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: zoneapi-db-secret
              key: password
        securityContext:
          runAsNonRoot: false
          runAsUser: 0
          allowPrivilegeEscalation: false
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "250m"
      volumes:
      - name: tmp
        emptyDir: {}
EOF

    echo -e "${GREEN}✅ Migration job created${NC}"
    return 0
}

# Main execution
main() {
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "${RED}❌ Namespace '$NAMESPACE' does not exist${NC}"
        exit 1
    fi

    # Cleanup old jobs first
    cleanup_old_jobs

    # Wait a moment for cleanup
    sleep 5

    # Run migration
    if run_migration "$IMAGE_TAG"; then
        local job_name="zoneapi-migration-$(echo "$IMAGE_TAG" | tr '.:' '-')"

        # Wait for completion
        if wait_for_job "$job_name" "$TIMEOUT"; then
            get_job_logs "$job_name"
            echo -e "${GREEN}🎉 Database migration completed successfully!${NC}"
            exit 0
        else
            echo -e "${RED}❌ Migration failed. Showing logs:${NC}"
            get_job_logs "$job_name"
            exit 1
        fi
    else
        echo -e "${RED}❌ Failed to create migration job${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
