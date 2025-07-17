#!/bin/bash

# Docker Image Size and ACR Connectivity Checker
# Helps diagnose slow image pull issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to log with timestamp
log_with_timestamp() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC')
    
    case "$level" in
        "ERROR")   echo -e "${RED}[$timestamp] ❌ ERROR: $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[$timestamp] ✅ SUCCESS: $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}[$timestamp] ⚠️  WARNING: $message${NC}" ;;
        "INFO")    echo -e "${BLUE}[$timestamp] ℹ️  INFO: $message${NC}" ;;
        "DEBUG")   echo -e "${PURPLE}[$timestamp] 🔍 DEBUG: $message${NC}" ;;
        *)         echo -e "[$timestamp] $level: $message" ;;
    esac
}

echo "=== 🐳 DOCKER IMAGE SIZE AND ACR CONNECTIVITY CHECKER ==="
echo ""

# Get configuration
ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:-}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_NAME="${IMAGE_NAME:-zoneapi}"

# Try to get ACR info from Terraform if not provided
if [ -z "$ACR_LOGIN_SERVER" ]; then
    log_with_timestamp "INFO" "Attempting to get ACR info from Terraform..."
    if command -v terraform &> /dev/null && [ -d "terraform" ]; then
        cd terraform
        ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server 2>/dev/null || echo "")
        cd ..
    fi
fi

if [ -z "$ACR_LOGIN_SERVER" ]; then
    log_with_timestamp "ERROR" "ACR_LOGIN_SERVER not provided and couldn't get from Terraform"
    echo "Please set ACR_LOGIN_SERVER environment variable"
    exit 1
fi

FULL_IMAGE_PATH="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

log_with_timestamp "INFO" "Checking image: $FULL_IMAGE_PATH"
echo ""

# Check Azure CLI authentication
log_with_timestamp "INFO" "Checking Azure CLI authentication..."
if az account show &>/dev/null; then
    SUBSCRIPTION=$(az account show --query name -o tsv)
    log_with_timestamp "SUCCESS" "Authenticated to Azure subscription: $SUBSCRIPTION"
else
    log_with_timestamp "ERROR" "Not authenticated to Azure CLI"
    echo "Run: az login"
    exit 1
fi

echo ""

# Check ACR connectivity
log_with_timestamp "INFO" "Testing ACR connectivity..."
ACR_NAME=$(echo "$ACR_LOGIN_SERVER" | cut -d'.' -f1)

if az acr show --name "$ACR_NAME" &>/dev/null; then
    log_with_timestamp "SUCCESS" "ACR is accessible: $ACR_NAME"
    
    # Get ACR details
    ACR_SKU=$(az acr show --name "$ACR_NAME" --query sku.name -o tsv)
    ACR_LOCATION=$(az acr show --name "$ACR_NAME" --query location -o tsv)
    log_with_timestamp "INFO" "ACR SKU: $ACR_SKU, Location: $ACR_LOCATION"
else
    log_with_timestamp "ERROR" "Cannot access ACR: $ACR_NAME"
    exit 1
fi

echo ""

# Check if image exists in ACR
log_with_timestamp "INFO" "Checking if image exists in ACR..."
if az acr repository show --name "$ACR_NAME" --repository "$IMAGE_NAME" &>/dev/null; then
    log_with_timestamp "SUCCESS" "Repository exists: $IMAGE_NAME"
    
    # Check specific tag
    if az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_NAME" --output tsv | grep -q "^$IMAGE_TAG$"; then
        log_with_timestamp "SUCCESS" "Image tag exists: $IMAGE_TAG"
        
        # Get image details
        IMAGE_MANIFEST=$(az acr repository show-manifests --name "$ACR_NAME" --repository "$IMAGE_NAME" --query "[?tags[0]=='$IMAGE_TAG']" -o json)
        if [ "$IMAGE_MANIFEST" != "[]" ]; then
            IMAGE_SIZE=$(echo "$IMAGE_MANIFEST" | jq -r '.[0].imageSize // "unknown"')
            CREATED_TIME=$(echo "$IMAGE_MANIFEST" | jq -r '.[0].createdTime // "unknown"')
            
            if [ "$IMAGE_SIZE" != "unknown" ] && [ "$IMAGE_SIZE" != "null" ]; then
                # Convert bytes to MB
                IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))
                log_with_timestamp "INFO" "Image size: ${IMAGE_SIZE_MB} MB"
                log_with_timestamp "INFO" "Created: $CREATED_TIME"
                
                # Provide size guidance
                if [ "$IMAGE_SIZE_MB" -gt 500 ]; then
                    log_with_timestamp "WARNING" "Large image (>500MB) - expect 2-3 minute pull times"
                elif [ "$IMAGE_SIZE_MB" -gt 200 ]; then
                    log_with_timestamp "INFO" "Medium image (>200MB) - expect 1-2 minute pull times"
                else
                    log_with_timestamp "SUCCESS" "Small image (<200MB) - should pull quickly"
                fi
            else
                log_with_timestamp "WARNING" "Could not determine image size"
            fi
        fi
    else
        log_with_timestamp "ERROR" "Image tag does not exist: $IMAGE_TAG"
        echo "Available tags:"
        az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_NAME" --output table
        exit 1
    fi
else
    log_with_timestamp "ERROR" "Repository does not exist: $IMAGE_NAME"
    echo "Available repositories:"
    az acr repository list --name "$ACR_NAME" --output table
    exit 1
fi

echo ""

# Check AKS node connectivity to ACR
log_with_timestamp "INFO" "Testing image pull capability from AKS..."
if command -v kubectl &> /dev/null; then
    if kubectl cluster-info &>/dev/null; then
        log_with_timestamp "SUCCESS" "Connected to Kubernetes cluster"
        
        # Get node information
        NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
        log_with_timestamp "INFO" "Cluster has $NODE_COUNT node(s)"
        
        # Check if image is already on nodes
        log_with_timestamp "INFO" "Checking if image is cached on nodes..."
        CACHED_NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read node; do
            if kubectl describe node "$node" | grep -q "$FULL_IMAGE_PATH"; then
                echo "$node"
            fi
        done | wc -l)
        
        if [ "$CACHED_NODES" -gt 0 ]; then
            log_with_timestamp "SUCCESS" "Image is cached on $CACHED_NODES node(s)"
        else
            log_with_timestamp "INFO" "Image not cached - first pull will take longer"
        fi
    else
        log_with_timestamp "WARNING" "Not connected to Kubernetes cluster"
    fi
else
    log_with_timestamp "WARNING" "kubectl not available"
fi

echo ""

# Recommendations
log_with_timestamp "INFO" "=== RECOMMENDATIONS ==="
echo ""
echo "Based on analysis:"

if [ -n "$IMAGE_SIZE_MB" ] && [ "$IMAGE_SIZE_MB" -gt 300 ]; then
    echo "🔧 Consider optimizing Docker image:"
    echo "   - Use multi-stage builds"
    echo "   - Use smaller base images (alpine variants)"
    echo "   - Remove unnecessary packages and files"
    echo "   - Minimize layers"
fi

echo ""
echo "⏱️ For migration timeouts:"
echo "   - Current timeout: 180 seconds (3 minutes)"
echo "   - Recommended for large images: 300 seconds (5 minutes)"
echo "   - Update TIMEOUT environment variable if needed"

echo ""
echo "🚀 To speed up subsequent deployments:"
echo "   - Images will be cached after first pull"
echo "   - Consider using imagePullPolicy: IfNotPresent"
echo "   - Pre-pull images during maintenance windows"

echo ""
log_with_timestamp "SUCCESS" "Image connectivity check completed" 