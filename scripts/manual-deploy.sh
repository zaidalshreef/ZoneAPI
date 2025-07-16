#!/bin/bash

# Manual deployment script for ZoneAPI without Helm
# This script helps troubleshoot Helm issues by deploying directly with kubectl

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1${NC}"
}

# Check if required environment variables are set
check_env_vars() {
    print_status "Checking required environment variables..."

    local required_vars=("ACR_REGISTRY" "DB_HOST" "POSTGRES_ADMIN_PASSWORD")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables: ${missing_vars[*]}"
        echo "Please set the following environment variables:"
        echo "  export ACR_REGISTRY=your-acr-registry.azurecr.io"
        echo "  export DB_HOST=your-postgres-server.postgres.database.azure.com"
        echo "  export POSTGRES_ADMIN_PASSWORD=your-password"
        exit 1
    fi

    print_success "All required environment variables are set"
}

# Function to check current secrets
check_secrets() {
    print_status "Checking existing secrets in Kubernetes cluster..."

    echo "=== All secrets in default namespace ==="
    kubectl get secrets -o wide || print_warning "Could not list secrets"

    echo ""
    echo "=== Checking for zoneapi-db-secret specifically ==="
    if kubectl get secret zoneapi-db-secret &>/dev/null; then
        print_success "Secret 'zoneapi-db-secret' exists"

        echo ""
        echo "=== Secret details ==="
        kubectl describe secret zoneapi-db-secret

        echo ""
        echo "=== Secret data keys ==="
        kubectl get secret zoneapi-db-secret -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "No jq available, showing raw data keys"

        echo ""
        echo "=== Checking password key specifically ==="
        if kubectl get secret zoneapi-db-secret -o jsonpath='{.data.password}' &>/dev/null; then
            print_success "Password key exists in secret"
            # Decode and show first few characters for verification (masked)
            local password_b64=$(kubectl get secret zoneapi-db-secret -o jsonpath='{.data.password}')
            local password_decoded=$(echo "$password_b64" | base64 -d)
            local password_masked="${password_decoded:0:3}***"
            echo "Password preview: $password_masked (length: ${#password_decoded})"
        else
            print_error "Password key missing in secret!"
        fi
    else
        print_warning "Secret 'zoneapi-db-secret' does not exist"
    fi

    echo ""
    echo "=== Checking for other ZoneAPI-related secrets ==="
    kubectl get secrets | grep -i zone || print_warning "No ZoneAPI-related secrets found"
}

# Function to prepare deployment files
prepare_deployment_files() {
    print_status "Preparing deployment files with current environment..."

    # Find the repository root directory (where manual-deploy exists)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_root="$(cd "$script_dir/.." && pwd)"

    print_status "Script directory: $script_dir"
    print_status "Repository root: $repo_root"
    print_status "Current working directory: $(pwd)"

    # Check if manual-deploy exists in repo root
    if [ ! -d "$repo_root/manual-deploy" ]; then
        # Try current directory
        repo_root="$(pwd)"
        print_status "Trying current directory as repo root: $repo_root"
    fi

    local temp_dir="$repo_root/manual-deploy/temp"
    print_status "Final temp directory: $temp_dir"

    mkdir -p "$temp_dir"

    # Check if manual-deploy files exist
    local source_dir="$repo_root/manual-deploy"
    if [ ! -d "$source_dir" ]; then
        print_error "manual-deploy directory not found: $source_dir"
        print_status "Available directories in $repo_root:"
        ls -la "$repo_root"
        print_status "Available directories in current dir $(pwd):"
        ls -la "$(pwd)"
        exit 1
    fi

    print_status "Looking for deployment files in: $source_dir"
    ls -la "$source_dir"

    # Copy files and replace placeholders
    local files_found=0
    for file in "$source_dir"/0*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            print_status "Preparing $filename..."

            # Replace placeholders with actual values
            sed -e "s|ACR_REGISTRY_PLACEHOLDER|$ACR_REGISTRY|g" \
                -e "s|DB_HOST_PLACEHOLDER|$DB_HOST|g" \
                "$file" >"$temp_dir/$filename"

            if [ -f "$temp_dir/$filename" ]; then
                print_success "Prepared $temp_dir/$filename"
                ((files_found++))
            else
                print_error "Failed to create $temp_dir/$filename"
            fi
        fi
    done

    if [ $files_found -eq 0 ]; then
        print_error "No deployment files found in $source_dir"
        print_status "Repository root: $repo_root"
        print_status "Looking for files matching: $source_dir/0*.yaml"
        exit 1
    fi

    print_success "Prepared $files_found deployment files"
    echo "$temp_dir"
}

# Function to update secret with correct password
update_secret() {
    print_status "Updating secret with correct password..."

    # Encode password
    local password_b64=$(echo -n "$POSTGRES_ADMIN_PASSWORD" | base64 -w 0)

    # Create/update secret
    kubectl create secret generic zoneapi-db-secret \
        --from-literal=password="$POSTGRES_ADMIN_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Secret updated successfully"
}

# Function to deploy resources
deploy_resources() {
    local temp_dir="$1"

    print_status "Deploying resources to Kubernetes..."
    print_status "Received temp directory path: '$temp_dir'"
    print_status "Current working directory: $(pwd)"

    # Ensure we have an absolute path
    if [[ ! "$temp_dir" = /* ]]; then
        temp_dir="$(pwd)/$temp_dir"
        print_status "Converted to absolute path: $temp_dir"
    fi

    # List what's actually in the temp directory
    if [ -d "$temp_dir" ]; then
        print_status "✓ Temp directory exists"
        print_status "Files in temp directory:"
        ls -la "$temp_dir"
    else
        print_error "✗ Temp directory $temp_dir does not exist!"

        # Try to find where it might be
        print_status "Searching for manual-deploy directories..."
        find "$(pwd)" -name "manual-deploy" -type d 2>/dev/null || true
        print_status "Searching for temp directories..."
        find "$(pwd)" -name "temp" -type d 2>/dev/null || true

        exit 1
    fi

    # Deploy in order: secret, migration job, deployment, service
    local files=("02-migration-job.yaml" "03-deployment.yaml" "04-service.yaml")
    # Note: Skipping 01-secret.yaml since we create the secret separately

    local deployed_count=0
    for file in "${files[@]}"; do
        local filepath="$temp_dir/$file"
        if [[ -f "$filepath" ]]; then
            print_status "Deploying $file..."
            print_status "File content preview:"
            head -10 "$filepath"
            echo "..."

            if kubectl apply -f "$filepath"; then
                print_success "Applied $file"
                ((deployed_count++))
            else
                print_error "Failed to apply $file"
                print_status "Full file content:"
                cat "$filepath"
                exit 1
            fi
        else
            print_error "File $filepath not found!"
            print_status "Expected files in $temp_dir:"
            find "$temp_dir" -name "*.yaml" -type f || echo "No YAML files found"
            exit 1
        fi
    done

    print_success "Deployed $deployed_count resources successfully"
}

# Function to monitor migration job
monitor_migration() {
    print_status "Monitoring migration job..."

    # Wait for job to appear
    local max_wait=60
    local count=0

    while ! kubectl get job zoneapi-migration-latest &>/dev/null && [[ $count -lt $max_wait ]]; do
        print_status "Waiting for migration job to be created... ($count/$max_wait)"
        sleep 2
        ((count++))
    done

    if ! kubectl get job zoneapi-migration-latest &>/dev/null; then
        print_error "Migration job was not created after ${max_wait} seconds"
        return 1
    fi

    print_success "Migration job found, monitoring progress..."

    # Monitor job status
    local timeout=1200 # 20 minutes
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local job_status=$(kubectl get job zoneapi-migration-latest -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")

        if [[ "$job_status" == "Complete" ]]; then
            print_success "Migration job completed successfully!"
            break
        elif [[ "$job_status" == "Failed" ]]; then
            print_error "Migration job failed!"
            echo ""
            echo "=== Job status ==="
            kubectl describe job zoneapi-migration-latest
            echo ""
            echo "=== Pod logs ==="
            kubectl logs -l job-name=zoneapi-migration-latest --tail=50
            return 1
        fi

        print_status "Migration in progress... (${elapsed}s/${timeout}s)"

        # Show recent logs every 30 seconds
        if ((elapsed % 30 == 0)); then
            echo ""
            echo "=== Recent migration logs ==="
            kubectl logs -l job-name=zoneapi-migration-latest --tail=10 --since=30s 2>/dev/null || echo "No logs available yet"
            echo ""
        fi

        sleep 10
        ((elapsed += 10))
    done

    if [[ $elapsed -ge $timeout ]]; then
        print_error "Migration job timed out after ${timeout} seconds"
        return 1
    fi
}

# Function to check deployment status
check_deployment() {
    print_status "Checking application deployment status..."

    # Wait for deployment to be ready
    kubectl rollout status deployment/zoneapi --timeout=300s

    if [[ $? -eq 0 ]]; then
        print_success "Application deployment is ready!"

        echo ""
        echo "=== Deployment status ==="
        kubectl get deployment zoneapi -o wide

        echo ""
        echo "=== Pod status ==="
        kubectl get pods -l app.kubernetes.io/name=zoneapi -o wide

        echo ""
        echo "=== Service status ==="
        kubectl get service zoneapi -o wide

    else
        print_error "Application deployment failed or timed out"

        echo ""
        echo "=== Deployment status ==="
        kubectl describe deployment zoneapi

        echo ""
        echo "=== Pod logs ==="
        kubectl logs -l app.kubernetes.io/name=zoneapi --tail=20

        return 1
    fi
}

# Function to cleanup temp files
cleanup() {
    print_status "Cleaning up temporary files..."

    # Find the repository root (same logic as prepare_deployment_files)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_root="$(cd "$script_dir/.." && pwd)"

    if [ ! -d "$repo_root/manual-deploy" ]; then
        repo_root="$(pwd)"
    fi

    local temp_dir="$repo_root/manual-deploy/temp"
    print_status "Removing: $temp_dir"

    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
        print_success "Cleanup completed"
    else
        print_warning "Temp directory not found: $temp_dir"
    fi
}

# Main function
main() {
    print_status "Starting manual ZoneAPI deployment..."

    # Check prerequisites
    check_env_vars

    # Check current state
    check_secrets

    # Prepare files
    local temp_dir=$(prepare_deployment_files)
    print_status "Received temp directory path: '$temp_dir'"

    # Update secret with correct password
    update_secret

    # Deploy resources
    print_status "Passing temp directory to deploy_resources: '$temp_dir'"
    deploy_resources "$temp_dir"

    # Monitor migration
    if monitor_migration; then
        print_success "Migration completed successfully"

        # Check deployment
        if check_deployment; then
            print_success "Manual deployment completed successfully!"

            echo ""
            echo "=== Next Steps ==="
            echo "1. Check application health: kubectl port-forward service/zoneapi 8080:8080"
            echo "2. Test API: curl http://localhost:8080/health"
            echo "3. View logs: kubectl logs -l app.kubernetes.io/name=zoneapi -f"
            echo "4. If everything works, we can debug Helm configuration"
        else
            print_error "Application deployment failed"
            cleanup
            exit 1
        fi
    else
        print_error "Migration failed"
        cleanup
        exit 1
    fi

    # Cleanup
    cleanup
}

# Show usage if no arguments
if [[ $# -eq 0 ]]; then
    echo "Manual ZoneAPI Deployment Script"
    echo ""
    echo "This script deploys ZoneAPI manually without Helm to help troubleshoot deployment issues."
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  deploy       - Full deployment (default)"
    echo "  check        - Only check secrets and current state"
    echo "  clean        - Remove manual deployment resources"
    echo ""
    echo "Required environment variables:"
    echo "  ACR_REGISTRY           - Azure Container Registry URL"
    echo "  DB_HOST               - PostgreSQL server hostname"
    echo "  POSTGRES_ADMIN_PASSWORD - Database password"
    echo ""
    echo "Example:"
    echo "  export ACR_REGISTRY=myregistry.azurecr.io"
    echo "  export DB_HOST=mypostgres.postgres.database.azure.com"
    echo "  export POSTGRES_ADMIN_PASSWORD=mypassword"
    echo "  $0 deploy"
    echo ""
    exit 0
fi

# Handle commands
case "${1:-deploy}" in
"deploy")
    main
    ;;
"check")
    check_env_vars
    check_secrets
    ;;
"clean")
    print_status "Removing manual deployment resources..."
    kubectl delete deployment zoneapi --ignore-not-found=true
    kubectl delete service zoneapi --ignore-not-found=true
    kubectl delete job zoneapi-migration-latest --ignore-not-found=true
    kubectl delete secret zoneapi-db-secret --ignore-not-found=true
    print_success "Manual deployment resources removed"
    ;;
*)
    echo "Unknown command: $1"
    echo "Use '$0' to see usage information"
    exit 1
    ;;
esac
