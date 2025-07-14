# Core configuration variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "zoneapi"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "West US"
}

# AKS configuration variables
variable "aks_node_count" {
  description = "Number of nodes in the AKS cluster"
  type        = number
  default     = 1
}

variable "aks_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_B2s"
}

# PostgreSQL configuration variables
variable "postgres_admin_username" {
  description = "Administrator username for PostgreSQL server"
  type        = string
  default     = "postgres"
}

variable "postgres_admin_password" {
  description = "Administrator password for PostgreSQL server"
  type        = string
  sensitive   = true
} 