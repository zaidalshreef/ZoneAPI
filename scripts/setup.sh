#!/bin/bash

# ZoneAPI Setup Script
# This script helps set up the initial Azure infrastructure and GitHub secrets

set -e

echo "🚀 ZoneAPI Setup Script"
echo "======================="

# Check if required tools are installed
check_tools() {
    echo "Checking required tools..."

    if ! command -v az &>/dev/null; then
        echo "❌ Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    if ! command -v terraform &>/dev/null; then
        echo "❌ Terraform is not installed. Please install it from https://www.terraform.io/downloads.html"
        exit 1
    fi

    if ! command -v kubectl &>/dev/null; then
        echo "❌ kubectl is not installed. Please install it from https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    if ! command -v helm &>/dev/null; then
        echo "❌ Helm is not installed. Please install it from https://helm.sh/docs/intro/install/"
        exit 1
    fi

    echo "✅ All required tools are installed"
}

# Azure login and setup
azure_setup() {
    echo "Setting up Azure resources..."

    # Check if logged in
    if ! az account show &>/dev/null; then
        echo "Please login to Azure:"
        az login
    fi

    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    echo "Using subscription: $SUBSCRIPTION_ID"

    # Create service principal
    echo "Creating service principal..."
    SP_OUTPUT=$(az ad sp create-for-rbac --name "zoneapi-sp-$(date +%s)" --role contributor --scopes /subscriptions/$SUBSCRIPTION_ID --output json)

    # Extract values
    CLIENT_ID=$(echo $SP_OUTPUT | jq -r '.appId')
    CLIENT_SECRET=$(echo $SP_OUTPUT | jq -r '.password')
    TENANT_ID=$(echo $SP_OUTPUT | jq -r '.tenant')

    echo "✅ Service principal created successfully"
    echo ""
    echo "📋 GitHub Secrets to configure:"
    echo "ARM_CLIENT_ID: $CLIENT_ID"
    echo "ARM_CLIENT_SECRET: $CLIENT_SECRET"
    echo "ARM_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    echo "ARM_TENANT_ID: $TENANT_ID"
    echo "AZURE_CREDENTIALS: $SP_OUTPUT"
    echo ""
    echo "⚠️  Please save these values securely and configure them as GitHub secrets"
}

# Generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Create terraform.tfvars
create_terraform_vars() {
    echo "Creating terraform.tfvars..."

    read -p "Enter project name [zoneapi]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-zoneapi}

    read -p "Enter environment [dev]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-dev}

    read -p "Enter Azure region [East US]: " LOCATION
    LOCATION=${LOCATION:-"East US"}

    # Generate random password
    DB_PASSWORD=$(generate_password)

    cat >terraform/terraform.tfvars <<EOF
project_name = "$PROJECT_NAME"
environment  = "$ENVIRONMENT"
location     = "$LOCATION"
aks_node_count = 2
aks_vm_size    = "Standard_D2s_v3"
postgres_admin_username = "postgres"
postgres_admin_password = "$DB_PASSWORD"
EOF

    echo "✅ terraform.tfvars created"
    echo "📋 Additional GitHub secret to configure:"
    echo "POSTGRES_ADMIN_PASSWORD: $DB_PASSWORD"
}

# Terraform initialization
terraform_init() {
    echo "Initializing Terraform..."
    cd terraform
    terraform init
    terraform validate
    echo "✅ Terraform initialized and validated"
    cd ..
}

# Helm chart validation
validate_helm() {
    echo "Validating Helm chart..."
    helm lint charts/zoneapi
    echo "✅ Helm chart validated"
}

# Main execution
main() {
    echo "Starting ZoneAPI setup..."

    check_tools

    read -p "Do you want to set up Azure resources? (y/n): " SETUP_AZURE
    if [[ $SETUP_AZURE =~ ^[Yy]$ ]]; then
        azure_setup
    fi

    read -p "Do you want to create terraform.tfvars? (y/n): " CREATE_VARS
    if [[ $CREATE_VARS =~ ^[Yy]$ ]]; then
        create_terraform_vars
    fi

    read -p "Do you want to initialize Terraform? (y/n): " INIT_TERRAFORM
    if [[ $INIT_TERRAFORM =~ ^[Yy]$ ]]; then
        terraform_init
    fi

    validate_helm

    echo ""
    echo "🎉 Setup completed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Configure the GitHub secrets mentioned above"
    echo "2. Push your code to the main branch to trigger the CI/CD pipeline"
    echo "3. Monitor the deployment in GitHub Actions"
    echo "4. Test your deployed application"
    echo ""
    echo "📚 For more information, check the README.md file"
}

# Run main function
main "$@"
