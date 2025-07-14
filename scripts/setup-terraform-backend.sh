#!/bin/bash

# Setup Azure Storage Account for Terraform State Backend
# This script creates the required Azure resources for storing Terraform state

set -e

echo "Setting up Terraform state backend..."

# Variables
RESOURCE_GROUP_NAME="rg-terraform-state"
STORAGE_ACCOUNT_NAME="tfstatezoneapi"
CONTAINER_NAME="tfstate"
LOCATION="West US"

# Create resource group
echo "Creating resource group: $RESOURCE_GROUP_NAME"
az group create --name $RESOURCE_GROUP_NAME --location "$LOCATION"

# Create storage account
echo "Creating storage account: $STORAGE_ACCOUNT_NAME"
az storage account create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $STORAGE_ACCOUNT_NAME \
    --sku Standard_LRS \
    --encryption-services blob \
    --kind StorageV2

# Create blob container
echo "Creating blob container: $CONTAINER_NAME"
az storage container create \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME

# Enable versioning for better state management
echo "Enabling blob versioning..."
az storage account blob-service-properties update \
    --account-name $STORAGE_ACCOUNT_NAME \
    --enable-versioning true

echo "✅ Terraform state backend setup complete!"
echo ""
echo "Backend configuration:"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  Location: $LOCATION"
echo ""
echo "ℹ️  Make sure to add this storage account name to your GitHub secrets if it's different from 'tfstatezoneapi'"
