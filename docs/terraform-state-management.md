# Terraform State Management

## Overview

This project uses Azure Storage Account as a remote backend for Terraform state management. This ensures that:

- 🔒 **State is persistent** across pipeline runs
- 🤝 **Team collaboration** is possible with shared state
- 🔐 **State locking** prevents concurrent modifications
- 📊 **State versioning** provides backup and recovery

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub        │    │   Azure Storage │    │   Azure         │
│   Actions       │───▶│   Account       │───▶│   Resources     │
│   (Terraform)   │    │   (State)       │    │   (Your App)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Backend Configuration

The Terraform backend is configured in `terraform/main.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstatezoneapi"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
```

## Automatic Setup

The pipeline automatically sets up the backend storage account if it doesn't exist:

1. **Check**: Verifies if storage account exists
2. **Create**: Runs `setup-terraform-backend.sh` if needed
3. **Initialize**: Runs `terraform init` with backend configuration

## Manual Setup

If you want to set up the backend manually:

```bash
# Login to Azure
az login

# Run the setup script
./scripts/setup-terraform-backend.sh
```

## Storage Account Details

- **Resource Group**: `rg-terraform-state`
- **Storage Account**: `tfstatezoneapi`
- **Container**: `tfstate`
- **Location**: West US
- **Features**: Versioning enabled, encryption at rest

## Security Considerations

1. **Access Control**: Only the service principal used by GitHub Actions can access the state
2. **Encryption**: State is encrypted at rest in Azure Storage
3. **Versioning**: Previous state versions are retained for recovery
4. **Locking**: Terraform automatically locks state during operations

## Troubleshooting

### State Lock Issues
If you encounter state lock errors:
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Backend Reconfiguration
If you need to change backend settings:
```bash
# Reconfigure backend
terraform init -reconfigure
```

### State Recovery
If state is corrupted:
1. Check Azure Storage Account for previous versions
2. Download previous state version
3. Replace current state file
4. Run `terraform plan` to verify

## Best Practices

1. ✅ **Never commit state files** to version control
2. ✅ **Use consistent naming** for resources
3. ✅ **Run terraform plan** before apply
4. ✅ **Use workspaces** for multiple environments
5. ✅ **Regular state backups** (automatic with versioning)

## Environment-Specific States

For multiple environments (dev, staging, prod):

```bash
# Create workspace
terraform workspace new dev

# Switch workspace
terraform workspace select dev

# List workspaces
terraform workspace list
```

Each workspace maintains separate state files in the same backend. 