#!/bin/bash

# Cleanup all migration jobs and pods script
# This script removes all migration-related resources for a clean start

set -e

NAMESPACE=${1:-"zoneapi"}
FORCE=${2:-false}

echo "=== 🧹 CLEANING UP ALL MIGRATION JOBS AND PODS ==="
echo "Namespace: $NAMESPACE"
echo "Force cleanup: $FORCE"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if kubectl is available and connected
check_kubectl() {
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        log_error "kubectl is not connected to any cluster"
        exit 1
    fi

    log_success "kubectl is available and connected"
}

# Function to check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_warning "Namespace '$NAMESPACE' does not exist"
        return 1
    fi

    log_success "Namespace '$NAMESPACE' exists"
    return 0
}

# Function to clean up migration jobs
cleanup_migration_jobs() {
    log_info "Cleaning up migration jobs..."

    # Get all migration jobs
    local migration_jobs=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$migration_jobs" ]; then
        log_info "No migration jobs found to clean up"
        return 0
    fi

    log_info "Found migration jobs: $migration_jobs"

    if [ "$FORCE" = "true" ]; then
        log_info "Force deleting migration jobs..."
        for job in $migration_jobs; do
            log_info "Deleting job: $job"
            kubectl delete job "$job" -n "$NAMESPACE" --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
        done
    else
        log_info "Gracefully deleting migration jobs..."
        for job in $migration_jobs; do
            log_info "Deleting job: $job"
            kubectl delete job "$job" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        done
    fi

    log_success "Migration jobs cleanup completed"
}

# Function to clean up migration pods
cleanup_migration_pods() {
    log_info "Cleaning up migration pods..."

    # Get all migration pods
    local migration_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$migration_pods" ]; then
        log_info "No migration pods found to clean up"
        return 0
    fi

    log_info "Found migration pods: $migration_pods"

    if [ "$FORCE" = "true" ]; then
        log_info "Force deleting migration pods..."
        for pod in $migration_pods; do
            log_info "Deleting pod: $pod"
            kubectl delete pod "$pod" -n "$NAMESPACE" --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
        done
    else
        log_info "Gracefully deleting migration pods..."
        for pod in $migration_pods; do
            log_info "Deleting pod: $pod"
            kubectl delete pod "$pod" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        done
    fi

    log_success "Migration pods cleanup completed"
}

# Function to clean up any orphaned resources
cleanup_orphaned_resources() {
    log_info "Cleaning up any orphaned migration resources..."

    # Clean up any pods that might have been left behind
    local orphaned_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Failed -l app.kubernetes.io/component=migration -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$orphaned_pods" ]; then
        log_info "Found orphaned failed pods: $orphaned_pods"
        for pod in $orphaned_pods; do
            log_info "Deleting orphaned pod: $pod"
            kubectl delete pod "$pod" -n "$NAMESPACE" --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
        done
    fi

    # Clean up any completed pods older than 1 hour
    local old_completed_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Succeeded -l app.kubernetes.io/component=migration -o jsonpath='{.items[?(@.status.startTime<"'$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)'")].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$old_completed_pods" ]; then
        log_info "Found old completed pods: $old_completed_pods"
        for pod in $old_completed_pods; do
            log_info "Deleting old completed pod: $pod"
            kubectl delete pod "$pod" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        done
    fi

    log_success "Orphaned resources cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."

    local remaining_jobs=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    local remaining_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$remaining_jobs" ] && [ -z "$remaining_pods" ]; then
        log_success "✅ Environment is clean! No migration jobs or pods remaining"
        return 0
    fi

    if [ -n "$remaining_jobs" ]; then
        log_warning "⚠️  Some jobs still exist: $remaining_jobs"
    fi

    if [ -n "$remaining_pods" ]; then
        log_warning "⚠️  Some pods still exist: $remaining_pods"
    fi

    return 1
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=== 📊 FINAL STATUS ==="

    echo "Migration Jobs:"
    kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration 2>/dev/null || echo "  No migration jobs found"

    echo ""
    echo "Migration Pods:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=migration 2>/dev/null || echo "  No migration pods found"

    echo ""
    echo "Namespace Events (last 10):"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10 2>/dev/null || echo "  No recent events"
}

# Main execution
main() {
    echo "Starting cleanup process..."

    # Check prerequisites
    check_kubectl

    if ! check_namespace; then
        log_warning "Namespace does not exist, nothing to clean up"
        exit 0
    fi

    # Show current state
    echo ""
    echo "=== 📊 CURRENT STATE ==="
    echo "Migration Jobs:"
    kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration 2>/dev/null || echo "  No migration jobs found"
    echo "Migration Pods:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=migration 2>/dev/null || echo "  No migration pods found"
    echo ""

    # Perform cleanup
    cleanup_migration_jobs
    cleanup_migration_pods
    cleanup_orphaned_resources

    # Wait a moment for resources to be deleted
    log_info "Waiting for resources to be deleted..."
    sleep 5

    # Verify cleanup
    if verify_cleanup; then
        log_success "🎉 Cleanup completed successfully!"
    else
        log_warning "⚠️  Cleanup completed with some remaining resources"
    fi

    # Show final status
    show_final_status
}

# Script usage
usage() {
    echo "Usage: $0 [namespace] [force]"
    echo "  namespace: Kubernetes namespace (default: zoneapi)"
    echo "  force: true/false - Force delete resources (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Clean up zoneapi namespace"
    echo "  $0 my-namespace       # Clean up my-namespace"
    echo "  $0 zoneapi true       # Force clean up zoneapi namespace"
    exit 1
}

# Handle script arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

# Run main function
main "$@"
