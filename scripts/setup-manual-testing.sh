#!/bin/bash

# Quick Setup Script for Manual Testing
# This script helps prepare your environment for manual testing

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ZoneAPI Manual Testing Setup ===${NC}"
echo "This script will help you prepare for manual testing"
echo ""

# Check if we're in the right directory
if [ ! -f "ZoneAPI.sln" ] || [ ! -d "terraform" ] || [ ! -d "charts" ]; then
    echo -e "${RED}❌ Error: Please run this script from the ZoneAPI project root directory${NC}"
    echo "Current directory: $(pwd)"
    echo "Expected files: ZoneAPI.sln, terraform/, charts/"
    exit 1
fi

echo -e "${GREEN}✅ Found project files${NC}"

# Make scripts executable
echo -e "${YELLOW}Making scripts executable...${NC}"
chmod +x scripts/*.sh 2>/dev/null || true
echo -e "${GREEN}✅ Scripts are executable${NC}"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check Azure CLI
if command -v az &>/dev/null; then
    echo -e "${GREEN}✅ Azure CLI is installed${NC}"
    if az account show &>/dev/null; then
        SUBSCRIPTION=$(az account show --query name --output tsv)
        echo -e "${GREEN}✅ Logged into Azure (Subscription: $SUBSCRIPTION)${NC}"
    else
        echo -e "${YELLOW}⚠️  Not logged into Azure. Run: az login${NC}"
    fi
else
    echo -e "${RED}❌ Azure CLI not installed. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli${NC}"
fi

# Check kubectl
if command -v kubectl &>/dev/null; then
    echo -e "${GREEN}✅ kubectl is installed${NC}"
    if kubectl cluster-info &>/dev/null; then
        CONTEXT=$(kubectl config current-context)
        echo -e "${GREEN}✅ Connected to Kubernetes (Context: $CONTEXT)${NC}"
    else
        echo -e "${YELLOW}⚠️  Not connected to any Kubernetes cluster${NC}"
    fi
else
    echo -e "${RED}❌ kubectl not installed. Install from: https://kubernetes.io/docs/tasks/tools/install-kubectl/${NC}"
fi

# Check Helm
if command -v helm &>/dev/null; then
    HELM_VERSION=$(helm version --short)
    echo -e "${GREEN}✅ Helm is installed ($HELM_VERSION)${NC}"
else
    echo -e "${RED}❌ Helm not installed. Install from: https://helm.sh/docs/intro/install/${NC}"
fi

# Check Docker (optional)
if command -v docker &>/dev/null; then
    echo -e "${GREEN}✅ Docker is installed${NC}"
else
    echo -e "${YELLOW}⚠️  Docker not installed (only needed for local image building)${NC}"
fi

# Check Terraform state
echo -e "${YELLOW}Checking Terraform state...${NC}"
if [ -f "terraform/terraform.tfstate" ] || [ -f "terraform/.terraform/terraform.tfstate" ]; then
    echo -e "${GREEN}✅ Terraform state found${NC}"
    
    cd terraform
    if terraform init -input=false &>/dev/null; then
        echo -e "${GREEN}✅ Terraform initialized${NC}"
        
        # Try to get key outputs
        RG=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
        AKS=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "")
        ACR=$(terraform output -raw acr_login_server 2>/dev/null || echo "")
        DB=$(terraform output -raw postgres_server_fqdn 2>/dev/null || echo "")
        
        if [ -n "$RG" ] && [ -n "$AKS" ] && [ -n "$ACR" ] && [ -n "$DB" ]; then
            echo -e "${GREEN}✅ All required Terraform outputs available${NC}"
            echo "  Resource Group: $RG"
            echo "  AKS Cluster: $AKS"  
            echo "  ACR: $ACR"
            echo "  Database: $DB"
        else
            echo -e "${YELLOW}⚠️  Some Terraform outputs missing. You may need to run 'terraform apply'${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Terraform needs initialization. Run 'cd terraform && terraform init'${NC}"
    fi
    cd ..
else
    echo -e "${YELLOW}⚠️  No Terraform state found. Infrastructure may not be deployed yet.${NC}"
fi

echo ""
echo -e "${BLUE}=== Next Steps ===${NC}"

if [ -n "$RG" ] && [ -n "$AKS" ] && [ -n "$ACR" ] && [ -n "$DB" ]; then
    echo -e "${GREEN}🚀 Ready for manual testing!${NC}"
    echo ""
    echo "Run the manual test script:"
    echo -e "${YELLOW}  ./scripts/test-manual-deployment.sh${NC}"
    echo ""
    echo "Or follow the manual testing guide:"
    echo -e "${YELLOW}  docs/manual-testing-guide.md${NC}"
else
    echo -e "${YELLOW}⚠️  Infrastructure setup needed first:${NC}"
    echo ""
    echo "1. Set up Terraform variables:"
    echo -e "${YELLOW}   cp terraform/terraform.tfvars.example terraform/terraform.tfvars${NC}"
    echo -e "${YELLOW}   # Edit terraform.tfvars with your values${NC}"
    echo ""
    echo "2. Deploy infrastructure:"
    echo -e "${YELLOW}   cd terraform${NC}"
    echo -e "${YELLOW}   terraform init${NC}"
    echo -e "${YELLOW}   terraform plan${NC}"
    echo -e "${YELLOW}   terraform apply${NC}"
    echo ""
    echo "3. Then run manual testing:"
    echo -e "${YELLOW}   ./scripts/test-manual-deployment.sh${NC}"
fi

echo ""
echo -e "${BLUE}=== Additional Resources ===${NC}"
echo "📖 Manual Testing Guide: docs/manual-testing-guide.md"
echo "🔧 Debug Scripts: scripts/debug-*.sh"
echo "📋 Quick Reference: docs/quick-reference.md"
echo "🚀 Full Documentation: README.md"

echo ""
echo -e "${GREEN}Setup complete! 🎉${NC}" 