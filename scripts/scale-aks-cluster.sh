#!/bin/bash

# Scale AKS Cluster for ZoneAPI
# This script helps scale the AKS cluster to accommodate resource requirements

set -e

# Configuration
RESOURCE_GROUP="rg-zoneapi-dev"
CLUSTER_NAME="aks-zoneapi-dev"
SUBSCRIPTION_ID="a4356e2f-4f1a-405b-95ab-0eaacea61ceb"

echo "=== AKS Cluster Scaling Tool ==="
echo "Current cluster: $CLUSTER_NAME in $RESOURCE_GROUP"

# Check current cluster status
echo "Checking current cluster status..."
az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query "{name:name,nodeResourceGroup:nodeResourceGroup,agentPoolProfiles:agentPoolProfiles[0].{name:name,count:count,vmSize:vmSize,osDiskSizeGb:osDiskSizeGb}}" --output table

# Check current node resource usage
echo -e "\nChecking current resource usage..."
kubectl top nodes 2>/dev/null || echo "Metrics server not available"

# Show current pods and their resource requests
echo -e "\nCurrent pod resource requests:"
kubectl get pods --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory" --no-headers | grep -v "<none>"

echo -e "\n=== Scaling Options ==="
echo "1. Scale node count (horizontal scaling)"
echo "2. Upgrade node size (vertical scaling)"
echo "3. Add new node pool"
echo "4. Show current pricing estimates"
echo "5. Exit"

read -p "Choose an option (1-5): " choice

case $choice in
1)
    current_count=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query "agentPoolProfiles[0].count" -o tsv)
    echo "Current node count: $current_count"
    read -p "Enter new node count (recommended: 2-3): " new_count

    echo "Scaling cluster to $new_count nodes..."
    az aks scale --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --node-count "$new_count"
    echo "✅ Cluster scaled successfully!"
    ;;
2)
    current_size=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query "agentPoolProfiles[0].vmSize" -o tsv)
    echo "Current VM size: $current_size"
    echo "Common sizes:"
    echo "  Standard_B2s  - 2 vCPU, 4 GB RAM (current likely)"
    echo "  Standard_B4ms - 4 vCPU, 16 GB RAM"
    echo "  Standard_D2s_v3 - 2 vCPU, 8 GB RAM"
    echo "  Standard_D4s_v3 - 4 vCPU, 16 GB RAM"
    echo ""
    echo "Note: VM size upgrade requires creating a new node pool"
    read -p "Enter new VM size: " new_size

    echo "Creating new node pool with size $new_size..."
    az aks nodepool add --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" --name "nodepool2" --node-count 2 --node-vm-size "$new_size"
    echo "✅ New node pool created!"
    echo "Remember to migrate workloads and delete old node pool if needed"
    ;;
3)
    read -p "Enter node pool name: " pool_name
    read -p "Enter VM size (e.g., Standard_D2s_v3): " vm_size
    read -p "Enter node count: " node_count

    echo "Creating new node pool..."
    az aks nodepool add --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" --name "$pool_name" --node-count "$node_count" --node-vm-size "$vm_size"
    echo "✅ Node pool created successfully!"
    ;;
4)
    echo "Estimated monthly costs (East US region):"
    echo "  Standard_B2s (2 vCPU, 4GB): ~$30-40/node"
    echo "  Standard_B4ms (4 vCPU, 16GB): ~$120-140/node"
    echo "  Standard_D2s_v3 (2 vCPU, 8GB): ~$70-80/node"
    echo "  Standard_D4s_v3 (4 vCPU, 16GB): ~$140-160/node"
    echo ""
    echo "Plus egress, storage, and other services"
    echo "Check current pricing: https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/"
    ;;
5)
    echo "Exiting..."
    exit 0
    ;;
*)
    echo "Invalid option"
    exit 1
    ;;
esac

echo -e "\n=== Post-scaling verification ==="
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "Updated cluster status:"
az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query "{name:name,agentPoolProfiles:agentPoolProfiles[].{name:name,count:count,vmSize:vmSize}}" --output table

echo "✅ Scaling completed!"
