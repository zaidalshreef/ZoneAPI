# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.1"
    }
  }
  required_version = ">= 1.0"

  # Remote backend for state management
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstatezoneapi"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}

  # Use Service Principal authentication in CI/CD
  use_cli                    = false
  use_msi                    = false
  use_oidc                   = false
  skip_provider_registration = true
}

# Create a random suffix for resources to avoid naming conflicts
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for common tags and naming
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  resource_prefix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_prefix}"
  location = var.location
  tags     = local.common_tags
}

# Create Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "acr${replace(local.resource_prefix, "-", "")}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  admin_enabled       = true
  tags                = local.common_tags
}

# Create PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "psql-${local.resource_prefix}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "14"
  administrator_login    = var.postgres_admin_username
  administrator_password = var.postgres_admin_password

  storage_mb = 32768
  sku_name   = "B_Standard_B1ms"

  # Enable public network access for AKS connectivity
  public_network_access_enabled = true

  # Authentication configuration
  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  tags = local.common_tags
}

# Create PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "zone_db" {
  name      = "zone"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Create PostgreSQL Firewall Rule for AKS
resource "azurerm_postgresql_flexible_server_firewall_rule" "aks_access" {
  name             = "aks-access"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# Create AKS Cluster with ACR integration
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-${local.resource_prefix}"

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  tags = local.common_tags
}

# NOTE: This role assignment requires "User Access Administrator" permissions
# If you get permission errors, grant the service principal higher permissions:
# az role assignment create --assignee <service-principal-id> --role "User Access Administrator" --scope /subscriptions/<subscription-id>
#
# resource "azurerm_role_assignment" "aks_acr_pull" {
#   scope                = azurerm_container_registry.acr.id
#   role_definition_name = "AcrPull"
#   principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
# } 