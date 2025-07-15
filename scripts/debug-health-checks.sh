#!/bin/bash

# Debug Health Check Issues for ZoneAPI
# This script helps diagnose why health checks are failing

set -e

echo "=== ZoneAPI Health Check Diagnostics ==="
echo "Timestamp: $(date)"

# Check if kubectl is connected
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ kubectl not connected to cluster"
    echo "Run: az aks get-credentials --resource-group rg-zoneapi-dev --name aks-zoneapi-dev"
    exit 1
fi

echo "✅ Connected to cluster"

# 1. Check pod status
echo -e "\n=== Pod Status ==="
if kubectl get namespace zoneapi &>/dev/null; then
    kubectl get pods -n zoneapi -o wide

    # Get pod names
    pod_names=$(kubectl get pods -n zoneapi -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$pod_names" ]; then
        for pod in $pod_names; do
            echo -e "\n--- Pod: $pod ---"
            kubectl describe pod $pod -n zoneapi | grep -A 20 "Events:"
        done
    else
        echo "No pods found in zoneapi namespace"
    fi
else
    echo "ZoneAPI namespace does not exist"
    exit 1
fi

# 2. Check service status
echo -e "\n=== Service Status ==="
kubectl get services -n zoneapi -o wide

# 3. Check endpoints
echo -e "\n=== Endpoints ==="
kubectl get endpoints -n zoneapi

# 4. Test health endpoint directly
echo -e "\n=== Direct Health Check Test ==="
pod_names=$(kubectl get pods -n zoneapi -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$pod_names" ]; then
    for pod in $pod_names; do
        echo -e "\n--- Testing health endpoint on pod: $pod ---"

        # Check if pod is running
        pod_status=$(kubectl get pod $pod -n zoneapi -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "Pod status: $pod_status"

        if [ "$pod_status" = "Running" ]; then
            # Test health endpoint
            echo "Testing /health endpoint..."
            kubectl exec -n zoneapi $pod -- curl -s -o /dev/null -w "HTTP Status: %{http_code}, Response Time: %{time_total}s\n" http://localhost:8080/health || echo "Health check failed"

            # Test root endpoint
            echo "Testing root endpoint..."
            kubectl exec -n zoneapi $pod -- curl -s -o /dev/null -w "HTTP Status: %{http_code}, Response Time: %{time_total}s\n" http://localhost:8080/ || echo "Root endpoint failed"

            # Check if application is listening on port 8080
            echo "Checking port 8080..."
            kubectl exec -n zoneapi $pod -- netstat -ln | grep 8080 || echo "Port 8080 not listening"

            # Check application logs
            echo "Recent application logs:"
            kubectl logs $pod -n zoneapi --tail=10 || echo "No logs available"
        else
            echo "Pod not running, skipping health check"
        fi
    done
else
    echo "No pods found to test"
fi

# 5. Check readiness and liveness probe configuration
echo -e "\n=== Probe Configuration ==="
kubectl get pods -n zoneapi -o jsonpath='{range .items[*]}{.metadata.name}{":\n"}{.spec.containers[0].livenessProbe}{"\n"}{.spec.containers[0].readinessProbe}{"\n\n"}{end}' || echo "No probe configuration found"

# 6. Port forward test
echo -e "\n=== Port Forward Test ==="
if [ -n "$pod_names" ]; then
    first_pod=$(echo $pod_names | awk '{print $1}')
    echo "Testing port forward to pod: $first_pod"

    # Start port forward in background
    kubectl port-forward -n zoneapi pod/$first_pod 8081:8080 &
    pf_pid=$!

    # Wait a moment for port forward to establish
    sleep 3

    # Test via port forward
    echo "Testing via port forward..."
    curl -s -o /dev/null -w "HTTP Status: %{http_code}, Response Time: %{time_total}s\n" http://localhost:8081/health || echo "Port forward test failed"

    # Clean up port forward
    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true
fi

# 7. Application startup analysis
echo -e "\n=== Application Startup Analysis ==="
if [ -n "$pod_names" ]; then
    for pod in $pod_names; do
        echo -e "\n--- Startup logs for pod: $pod ---"
        kubectl logs $pod -n zoneapi --since=2m | head -20 || echo "No startup logs available"
    done
fi

# 8. Environment variables check
echo -e "\n=== Environment Variables ==="
if [ -n "$pod_names" ]; then
    first_pod=$(echo $pod_names | awk '{print $1}')
    echo "Environment variables in pod: $first_pod"
    kubectl exec -n zoneapi $first_pod -- env | grep -E "(ASPNETCORE|DB_|ConnectionStrings)" || echo "No relevant environment variables found"
fi

# 9. Resource usage
echo -e "\n=== Resource Usage ==="
kubectl top pods -n zoneapi 2>/dev/null || echo "Metrics not available"

# 10. Recommendations
echo -e "\n=== Recommendations ==="
echo "1. If pods are CrashLoopBackOff:"
echo "   - Check application logs: kubectl logs <pod> -n zoneapi"
echo "   - Verify database connection string"
echo "   - Check if /health endpoint is implemented"

echo -e "\n2. If health checks return 503:"
echo "   - Application may still be starting up"
echo "   - Database connection might be failing"
echo "   - Health endpoint might need more time to initialize"

echo -e "\n3. Quick fixes:"
echo "   - Increase probe initialDelaySeconds: kubectl patch deployment zoneapi -n zoneapi -p '{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"zoneapi\",\"readinessProbe\":{\"initialDelaySeconds\":30}}]}}}}'"
echo "   - Check application startup: kubectl logs deployment/zoneapi -n zoneapi --follow"
echo "   - Force restart: kubectl rollout restart deployment/zoneapi -n zoneapi"

echo -e "\n4. Manual health check:"
echo "   kubectl port-forward svc/zoneapi 8080:8080 -n zoneapi &"
echo "   curl http://localhost:8080/health"

echo -e "\n=== Diagnostics Complete ==="
