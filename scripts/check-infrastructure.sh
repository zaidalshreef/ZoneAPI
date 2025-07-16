#!/bin/bash

# Check Infrastructure Status Script
# This script checks if Azure infrastructure is deployed and shows current status

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[⚠] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_status "Checking ZoneAPI Infrastructure Status..."
echo ""

# Check if we're logged into Azure
if ! az account show >/dev/null 2>&1; then
    print_error "Not logged into Azure. Please run: az login"
    exit 1
fi

print_success "Azure CLI logged in"
SUBSCRIPTION=$(az account show --query name -o tsv)
echo "  Subscription: $SUBSCRIPTION"
echo ""

# Check if Terraform backend exists
print_status "Checking Terraform backend..."
if az storage account show --name tfstatezoneapi --resource-group rg-terraform-state >/dev/null 2>&1; then
    print_success "Terraform backend storage account exists"
else
    print_error "Terraform backend storage account not found"
    echo "  Run: ./scripts/setup-terraform-backend.sh"
    exit 1
fi

# Check Terraform state
print_status "Checking Terraform state..."
cd terraform

if [ ! -f ".terraform/terraform.tfstate" ] && [ ! -f "terraform.tfstate" ]; then
    print_warning "Terraform not initialized in this directory"
    echo "  Initializing Terraform..."
    terraform init
fi

# Check if state exists and has resources
if terraform show >/dev/null 2>&1; then
    print_success "Terraform state found with deployed resources"

    echo ""
    print_status "Infrastructure Components:"

    # Check each component
    echo ""
    echo "🏗️  Resource Group:"
    if RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null); then
        print_success "  $RG_NAME"
        if az group show --name "$RG_NAME" >/dev/null 2>&1; then
            print_success "  Resource group exists in Azure"
        else
            print_error "  Resource group not found in Azure!"
        fi
    else
        print_error "  Resource group output not found"
    fi

    echo ""
    echo "🐳 Container Registry:"
    if ACR_NAME=$(terraform output -raw acr_login_server 2>/dev/null); then
        print_success "  $ACR_NAME"
        if az acr show --name "$(echo "$ACR_NAME" | cut -d'.' -f1)" >/dev/null 2>&1; then
            print_success "  ACR exists in Azure"

            # Check if images exist
            IMAGE_COUNT=$(az acr repository list --name "$(echo "$ACR_NAME" | cut -d'.' -f1)" --query "length(@)" -o tsv 2>/dev/null || echo "0")
            if [ "$IMAGE_COUNT" -gt 0 ]; then
                print_success "  ACR has $IMAGE_COUNT repositories"
                az acr repository list --name "$(echo "$ACR_NAME" | cut -d'.' -f1)" -o table 2>/dev/null || true
            else
                print_warning "  ACR has no repositories (no images pushed yet)"
            fi
        else
            print_error "  ACR not found in Azure!"
        fi
    else
        print_error "  ACR output not found"
    fi

    echo ""
    echo "☸️  Kubernetes Cluster:"
    if AKS_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null); then
        print_success "  $AKS_NAME"
        if az aks show --name "$AKS_NAME" --resource-group "$RG_NAME" >/dev/null 2>&1; then
            print_success "  AKS cluster exists in Azure"

            # Check cluster status
            CLUSTER_STATE=$(az aks show --name "$AKS_NAME" --resource-group "$RG_NAME" --query "powerState.code" -o tsv 2>/dev/null || echo "Unknown")
            if [ "$CLUSTER_STATE" = "Running" ]; then
                print_success "  AKS cluster is running"
            else
                print_warning "  AKS cluster state: $CLUSTER_STATE"
            fi
        else
            print_error "  AKS cluster not found in Azure!"
        fi
    else
        print_error "  AKS cluster output not found"
    fi

    echo ""
    echo "🐘 PostgreSQL Database:"
    if POSTGRES_HOST=$(terraform output -raw postgres_server_fqdn 2>/dev/null); then
        print_success "  $POSTGRES_HOST"
        if POSTGRES_NAME=$(terraform output -raw postgres_server_name 2>/dev/null); then
            if az postgres flexible-server show --name "$POSTGRES_NAME" --resource-group "$RG_NAME" >/dev/null 2>&1; then
                print_success "  PostgreSQL server exists in Azure"

                # Check server status
                SERVER_STATE=$(az postgres flexible-server show --name "$POSTGRES_NAME" --resource-group "$RG_NAME" --query "state" -o tsv 2>/dev/null || echo "Unknown")
                if [ "$SERVER_STATE" = "Ready" ]; then
                    print_success "  PostgreSQL server is ready"
                else
                    print_warning "  PostgreSQL server state: $SERVER_STATE"
                fi
            else
                print_error "  PostgreSQL server not found in Azure!"
            fi
        else
            print_error "  PostgreSQL server name output not found"
        fi
    else
        print_error "  PostgreSQL host output not found"
    fi

else
    print_error "No Terraform state found or state is empty"
    echo ""
    print_status "This means infrastructure has not been deployed yet."
    echo ""
    echo "To deploy infrastructure:"
    echo "1. Run the main CI/CD pipeline (push to master branch)"
    echo "2. Or manually run:"
    echo "   cd terraform"
    echo "   terraform plan"
    echo "   terraform apply"
    exit 1
fi

echo ""
print_status "All Terraform outputs:"
terraform output

echo ""
print_success "Infrastructure check completed!"
echo ""
echo "Next steps:"
echo "1. If infrastructure exists, you can run the manual deployment test"
echo "2. If any components are missing, run the main CI/CD pipeline"
echo "3. Check Azure portal for detailed resource status"
