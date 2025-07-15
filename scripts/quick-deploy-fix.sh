#!/bin/bash

# Quick Deploy Fix for ZoneAPI
# Implements user requirements: 30s timeout, max 3 retries

set -e

echo "=== ZoneAPI Quick Deploy Fix ==="
echo "Timeout: 30 seconds per attempt"
echo "Max retries: 3"
echo "Timestamp: $(date)"

# Configuration
MAX_ATTEMPTS=3
TIMEOUT_SECONDS=30
NAMESPACE="zoneapi"

# Check if kubectl is connected
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ kubectl not connected to cluster"
    echo "Run: az aks get-credentials --resource-group rg-zoneapi-dev --name aks-zoneapi-dev"
    exit 1
fi

echo "✅ Connected to cluster"

# Function to clean up failed deployment
cleanup_deployment() {
    echo "🧹 Cleaning up failed deployment..."

    # Force delete stuck pods
    kubectl delete pods --all -n $NAMESPACE --force --grace-period=0 2>/dev/null || true

    # Delete failed jobs
    kubectl delete jobs --all -n $NAMESPACE --force --grace-period=0 2>/dev/null || true

    # Remove failed helm release
    helm delete zoneapi --namespace $NAMESPACE 2>/dev/null || true

    echo "✅ Cleanup completed"
}

# Function to deploy with timeout and retries
deploy_with_retry() {
    local attempt=1

    while [ $attempt -le $MAX_ATTEMPTS ]; do
        echo "🚀 Deployment attempt $attempt of $MAX_ATTEMPTS"
        echo "⏱️  Timeout: ${TIMEOUT_SECONDS}s"

        # Start deployment with timeout
        if timeout ${TIMEOUT_SECONDS}s helm upgrade --install zoneapi ./charts/zoneapi \
            --namespace $NAMESPACE \
            --create-namespace \
            --wait \
            --atomic \
            --timeout=${TIMEOUT_SECONDS}s \
            --set replicaCount=1 \
            --set resources.requests.cpu=100m \
            --set resources.requests.memory=128Mi \
            --set resources.limits.cpu=200m \
            --set resources.limits.memory=256Mi \
            --set readinessProbe.initialDelaySeconds=10 \
            --set readinessProbe.failureThreshold=3 \
            --set livenessProbe.initialDelaySeconds=30 \
            --set livenessProbe.failureThreshold=3 \
            --set database.host="psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com" \
            --set database.password="${POSTGRES_ADMIN_PASSWORD:-}" \
            --debug; then

            echo "✅ Deployment successful on attempt $attempt!"
            echo "🎉 ZoneAPI deployed with fast timeout settings"
            return 0
        else
            echo "❌ Deployment failed on attempt $attempt (timeout: ${TIMEOUT_SECONDS}s)"

            if [ $attempt -lt $MAX_ATTEMPTS ]; then
                echo "⏳ Waiting 10 seconds before retry..."
                sleep 10
                cleanup_deployment
            fi

            ((attempt++))
        fi
    done

    echo "💥 All $MAX_ATTEMPTS deployment attempts failed!"
    echo "❌ Deployment cancelled after ${TIMEOUT_SECONDS}s timeout limit"
    return 1
}

# Function to quick patch existing deployment
quick_patch_deployment() {
    echo "🔧 Quick patching existing deployment..."

    # Update probe settings for faster failures
    kubectl patch deployment zoneapi -n $NAMESPACE -p '{
        "spec": {
            "template": {
                "spec": {
                    "terminationGracePeriodSeconds": 10,
                    "containers": [{
                        "name": "zoneapi",
                        "readinessProbe": {
                            "initialDelaySeconds": 10,
                            "periodSeconds": 5,
                            "timeoutSeconds": 3,
                            "failureThreshold": 3
                        },
                        "livenessProbe": {
                            "initialDelaySeconds": 30,
                            "periodSeconds": 10,
                            "timeoutSeconds": 3,
                            "failureThreshold": 3
                        }
                    }]
                }
            }
        }
    }' 2>/dev/null || echo "No existing deployment to patch"
}

# Check if deployment already exists
if kubectl get deployment zoneapi -n $NAMESPACE &>/dev/null; then
    echo "📦 Existing deployment found"
    read -p "Do you want to (1) patch existing deployment or (2) redeploy completely? [1/2]: " choice

    case $choice in
    1)
        quick_patch_deployment
        echo "✅ Deployment patched with fast timeout settings"
        exit 0
        ;;
    2)
        cleanup_deployment
        ;;
    *)
        echo "Invalid choice, proceeding with redeploy..."
        cleanup_deployment
        ;;
    esac
fi

# Execute deployment with retry logic
echo "🚀 Starting deployment with user requirements:"
echo "   - 30 second timeout per attempt"
echo "   - Maximum 3 retries"
echo "   - Fast failure on health check issues"

if deploy_with_retry; then
    echo -e "\n✅ Deployment completed successfully!"
    echo "📊 Checking deployment status..."

    # Quick status check
    kubectl get pods -n $NAMESPACE -o wide
    kubectl get services -n $NAMESPACE

    echo -e "\n🔍 Quick health check..."
    pod_name=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$pod_name" ]; then
        kubectl wait --for=condition=ready pod/$pod_name -n $NAMESPACE --timeout=30s || echo "Pod not ready within 30s"
    fi

    echo -e "\n📝 Quick debugging commands:"
    echo "   kubectl logs deployment/zoneapi -n $NAMESPACE --follow"
    echo "   kubectl describe pods -n $NAMESPACE"
    echo "   ./scripts/debug-health-checks.sh"
else
    echo -e "\n❌ Deployment failed after $MAX_ATTEMPTS attempts"
    echo "📋 Troubleshooting options:"
    echo "   1. Run diagnostics: ./scripts/debug-health-checks.sh"
    echo "   2. Check resources: ./scripts/diagnose-resources.sh"
    echo "   3. Scale cluster: ./scripts/scale-aks-cluster.sh"
    echo "   4. Manual cleanup: kubectl delete namespace $NAMESPACE"
    exit 1
fi
