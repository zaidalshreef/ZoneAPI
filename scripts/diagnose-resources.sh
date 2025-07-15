#!/bin/bash

# Resource Diagnostics and Cleanup for ZoneAPI
# This script analyzes current resource usage and provides fixes

set -e

echo "=== ZoneAPI Resource Diagnostics ==="
echo "Timestamp: $(date)"

# Check if kubectl is connected
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ kubectl not connected to cluster"
    echo "Run: az aks get-credentials --resource-group rg-zoneapi-dev --name aks-zoneapi-dev"
    exit 1
fi

echo "✅ Connected to cluster"

# 1. Cluster Overview
echo -e "\n=== Cluster Overview ==="
kubectl get nodes -o wide

# 2. Node Resource Capacity
echo -e "\n=== Node Resource Capacity ==="
kubectl describe nodes | grep -E "(Name:|Capacity:|Allocatable:)" | grep -A2 "Name:"

# 3. Current Resource Usage
echo -e "\n=== Current Resource Usage ==="
echo "Pods by namespace:"
kubectl get pods --all-namespaces --no-headers | awk '{print $1}' | sort | uniq -c | sort -nr

echo -e "\nResource requests across all pods:"
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.resources.requests.cpu}{"/"}{.resources.requests.memory}{" "}{end}{"\n"}{end}' | column -t

# 4. Failed/Pending Pods
echo -e "\n=== Problem Pods ==="
kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded

# 5. Recent Events (Scheduling Issues)
echo -e "\n=== Recent Scheduling Events ==="
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -E "(FailedScheduling|Insufficient|Preemption)" | tail -10

# 6. ZoneAPI Specific Issues
echo -e "\n=== ZoneAPI Deployment Status ==="
if kubectl get namespace zoneapi &>/dev/null; then
    echo "ZoneAPI namespace exists"

    echo "Deployments:"
    kubectl get deployments -n zoneapi -o wide

    echo "ReplicaSets:"
    kubectl get replicasets -n zoneapi -o wide

    echo "Pods:"
    kubectl get pods -n zoneapi -o wide

    echo "Jobs:"
    kubectl get jobs -n zoneapi -o wide

    echo "Recent events in zoneapi namespace:"
    kubectl get events -n zoneapi --sort-by='.lastTimestamp' | tail -10
else
    echo "ZoneAPI namespace does not exist"
fi

# 7. Cleanup Recommendations
echo -e "\n=== Cleanup Recommendations ==="

# Count completed jobs
completed_jobs=$(kubectl get jobs --all-namespaces --field-selector=status.successful=1 --no-headers 2>/dev/null | wc -l)
if [ "$completed_jobs" -gt 0 ]; then
    echo "🧹 Found $completed_jobs completed jobs that can be cleaned up"
    echo "Command: kubectl delete jobs --all-namespaces --field-selector=status.successful=1"
fi

# Count failed jobs
failed_jobs=$(kubectl get jobs --all-namespaces --field-selector=status.failed=1 --no-headers 2>/dev/null | wc -l)
if [ "$failed_jobs" -gt 0 ]; then
    echo "🧹 Found $failed_jobs failed jobs that can be cleaned up"
    echo "Command: kubectl delete jobs --all-namespaces --field-selector=status.failed=1"
fi

# Count evicted pods
evicted_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase=Failed --no-headers 2>/dev/null | grep Evicted | wc -l)
if [ "$evicted_pods" -gt 0 ]; then
    echo "🧹 Found $evicted_pods evicted pods that can be cleaned up"
    echo "Command: kubectl get pods --all-namespaces --field-selector=status.phase=Failed -o name | xargs kubectl delete"
fi

# 8. Resource Requirements Analysis
echo -e "\n=== Resource Requirements Analysis ==="
total_cpu_requests=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.cpu}{"\n"}{end}{end}' | grep -v '^$' | sed 's/m$//' | awk '{sum += $1} END {print sum "m"}')
total_memory_requests=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.memory}{"\n"}{end}{end}' | grep -v '^$' | sed 's/Mi$//' | awk '{sum += $1} END {print sum "Mi"}')

echo "Total CPU requests: $total_cpu_requests"
echo "Total Memory requests: $total_memory_requests"

node_cpu_capacity=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.capacity.cpu}{"\n"}{end}' | awk '{sum += $1} END {print sum * 1000 "m"}')
node_memory_capacity=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.capacity.memory}{"\n"}{end}' | sed 's/Ki$//' | awk '{sum += $1} END {print sum / 1024 "Mi"}')

echo "Total Node CPU capacity: $node_cpu_capacity"
echo "Total Node Memory capacity: $node_memory_capacity"

# 9. Quick Fixes
echo -e "\n=== Quick Fixes ==="
echo "1. Reduce ZoneAPI resource requirements:"
echo "   Edit charts/zoneapi/values.yaml - reduce replicaCount to 1, CPU requests to 100m"

echo -e "\n2. Clean up completed resources:"
echo "   kubectl delete jobs --all-namespaces --field-selector=status.successful=1"
echo "   kubectl delete pods --all-namespaces --field-selector=status.phase=Succeeded"

echo -e "\n3. Scale cluster (if needed):"
echo "   ./scripts/scale-aks-cluster.sh"

echo -e "\n4. Force pod deletion (if stuck):"
echo "   kubectl delete pods --all -n zoneapi --force --grace-period=0"

echo -e "\n5. Check specific deployment:"
echo "   kubectl describe deployment zoneapi -n zoneapi"
echo "   kubectl logs -l app.kubernetes.io/name=zoneapi -n zoneapi --tail=50"

# 10. Auto-cleanup option
echo -e "\n=== Auto-cleanup Option ==="
read -p "Do you want to automatically clean up completed jobs and failed pods? (y/N): " auto_cleanup

if [[ "$auto_cleanup" =~ ^[Yy]$ ]]; then
    echo "Cleaning up completed jobs..."
    kubectl delete jobs --all-namespaces --field-selector=status.successful=1 --timeout=30s || echo "No completed jobs to clean"

    echo "Cleaning up failed pods..."
    kubectl delete pods --all-namespaces --field-selector=status.phase=Failed --timeout=30s || echo "No failed pods to clean"

    echo "Cleaning up succeeded pods..."
    kubectl delete pods --all-namespaces --field-selector=status.phase=Succeeded --timeout=30s || echo "No succeeded pods to clean"

    echo "✅ Cleanup completed!"

    echo -e "\nUpdated cluster status:"
    kubectl get pods --all-namespaces --no-headers | awk '{print $3}' | sort | uniq -c
fi

echo -e "\n=== Diagnostics Complete ==="
echo "Check the output above for resource bottlenecks and recommendations."
