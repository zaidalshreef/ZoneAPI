#!/bin/bash

# Check available regions for PostgreSQL Flexible Server
echo "🔍 Checking available regions for PostgreSQL Flexible Server..."
echo "=================================================="

# Check if user is logged in to Azure
if ! az account show &>/dev/null; then
    echo "❌ Please login to Azure first: az login"
    exit 1
fi

echo "✅ Azure login verified"
echo ""

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
echo "📋 Subscription: $SUBSCRIPTION_NAME"
echo "🔑 Subscription ID: $SUBSCRIPTION_ID"
echo ""

# Check PostgreSQL provider registration
echo "🔍 Checking PostgreSQL provider registration..."
POSTGRES_PROVIDER=$(az provider show --namespace Microsoft.DBforPostgreSQL --query registrationState --output tsv)
if [ "$POSTGRES_PROVIDER" != "Registered" ]; then
    echo "⚠️  PostgreSQL provider not registered. Registering..."
    az provider register --namespace Microsoft.DBforPostgreSQL
    echo "✅ PostgreSQL provider registered"
else
    echo "✅ PostgreSQL provider already registered"
fi
echo ""

# List available regions for PostgreSQL Flexible Server
echo "🌍 Available regions for PostgreSQL Flexible Server:"
echo "======================================================"
az postgres flexible-server list-skus --location westus2 --query "[0].supportedVersions[0].supportedZones" --output table 2>/dev/null

# Common regions to check
REGIONS=("westus2" "centralus" "eastus" "westeurope" "northeurope" "southeastasia" "japaneast" "australiaeast")

echo ""
echo "🔍 Testing region availability:"
echo "================================"

for region in "${REGIONS[@]}"; do
    echo -n "Testing $region... "
    # Try to get PostgreSQL SKUs for the region
    result=$(az postgres flexible-server list-skus --location $region --query "[0].name" --output tsv 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "✅ Available"
    else
        echo "❌ Not available"
    fi
done

echo ""
echo "💡 Recommendation:"
echo "=================="
echo "1. Use one of the available regions above"
echo "2. Update terraform/variables.tf with the chosen region"
echo "3. Common working regions: West US 2, Central US, West Europe"
echo ""
echo "🔧 To update your Terraform configuration:"
echo "Edit terraform/variables.tf and change the location default value"
echo "Then run: terraform plan -var=\"location=YOUR_CHOSEN_REGION\""
