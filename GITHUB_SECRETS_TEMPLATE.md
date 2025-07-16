# GitHub Secrets Configuration Template

## Required GitHub Secrets for ZoneAPI CI/CD Pipeline

Configure these secrets in your GitHub repository to enable the complete 6-stage CI/CD pipeline with security scanning and automated deployment.

### 🔐 Azure Authentication Secrets

**Core Azure Service Principal Authentication:**
```
ARM_CLIENT_ID = <your-service-principal-client-id>
ARM_CLIENT_SECRET = <your-service-principal-client-secret>  
ARM_SUBSCRIPTION_ID = <your-azure-subscription-id>
ARM_TENANT_ID = <your-azure-tenant-id>
```

### 🔑 Azure Credentials JSON Format

**Combined Azure Credentials (Alternative Authentication Method):**
```json
AZURE_CREDENTIALS = {
  "clientId": "<your-service-principal-client-id>",
  "clientSecret": "<your-service-principal-client-secret>",
  "tenantId": "<your-azure-tenant-id>",
  "subscriptionId": "<your-azure-subscription-id>"
}
```

### 🗄️ Database Configuration

**PostgreSQL Database Password:**
```
POSTGRES_ADMIN_PASSWORD = <your-secure-database-password>
```

> **💡 Password Requirements:**
> - Minimum 12 characters
> - Include uppercase, lowercase, numbers, and special characters
> - Avoid common passwords or dictionary words
> - Example: `MySecureDB#2024!Zone`

## 🚀 How to Add Secrets to GitHub

### Step-by-Step Guide

1. **Navigate to Repository Settings**
   ```
   Your Repository → Settings → Secrets and variables → Actions
   ```

2. **Add Repository Secrets**
   - Click **"New repository secret"**
   - Enter the **exact** secret name from the list above
   - Paste the corresponding value
   - Click **"Add secret"**

3. **Verify All Secrets Added**
   Ensure all 5 required secrets are configured:
   - ✅ ARM_CLIENT_ID
   - ✅ ARM_CLIENT_SECRET  
   - ✅ ARM_SUBSCRIPTION_ID
   - ✅ ARM_TENANT_ID
   - ✅ POSTGRES_ADMIN_PASSWORD

## 📋 Complete Secrets Checklist

### Required Secrets (5 total)

| Secret Name | Description | Example/Format | Required |
|-------------|-------------|----------------|----------|
| `ARM_CLIENT_ID` | Service Principal Application ID | `12345678-1234-1234-1234-123456789012` | ✅ |
| `ARM_CLIENT_SECRET` | Service Principal Password/Secret | `abcDEF123456~_secretValue.123` | ✅ |
| `ARM_SUBSCRIPTION_ID` | Azure Subscription ID | `87654321-4321-4321-4321-210987654321` | ✅ |
| `ARM_TENANT_ID` | Azure Active Directory Tenant ID | `11111111-2222-3333-4444-555555555555` | ✅ |
| `POSTGRES_ADMIN_PASSWORD` | Database Administrator Password | `MySecureDB#2024!Zone` | ✅ |

### Auto-Generated Secrets (Handled by Pipeline)

These secrets are **automatically created** by the pipeline after infrastructure deployment:

| Secret Name | Description | Auto-Generated |
|-------------|-------------|----------------|
| `ACR_LOGIN_SERVER` | Container Registry URL | ✅ After Terraform |
| `ACR_USERNAME` | Container Registry Username | ✅ After Terraform |
| `ACR_PASSWORD` | Container Registry Password | ✅ After Terraform |

## 🛠️ Getting Secret Values

### Automated Setup (Recommended)

```bash
# Run the comprehensive setup script
./scripts/setup.sh

# This script will:
# ✅ Create Azure Service Principal
# ✅ Generate all required secret values
# ✅ Display formatted output for GitHub
# ✅ Validate Azure permissions
```

### Manual Azure Service Principal Creation

```bash
# Create service principal with Contributor role
az ad sp create-for-rbac \
  --name "zoneapi-deployment-sp" \
  --role contributor \
  --scopes /subscriptions/<your-subscription-id>

# Output will provide ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID
# Your subscription ID is ARM_SUBSCRIPTION_ID
```

### Get Azure Subscription Information

```bash
# Get current subscription details
az account show

# List all available subscriptions
az account list --output table

# Set specific subscription (if needed)
az account set --subscription "<subscription-id>"
```

## 🔒 Security Best Practices

### Secret Management Guidelines

- **🚫 Never commit secrets** to version control
- **🔄 Rotate secrets regularly** (every 90 days recommended)
- **👥 Limit access** to repository secrets to essential team members
- **📝 Document secret purposes** for team clarity
- **🔍 Monitor secret usage** in GitHub Actions logs

### Service Principal Permissions

Your service principal needs these Azure permissions:
- **Contributor** role on the subscription
- **Access to create** resource groups, AKS clusters, ACR, PostgreSQL
- **Key Vault access** (if using Azure Key Vault for additional secrets)

## 🔧 Troubleshooting

### Common Issues

#### ❌ "Authentication failed" Errors
**Cause:** Incorrect Azure credentials  
**Solution:** 
1. Verify all ARM_* secrets are correctly copied
2. Run `az account show` to confirm subscription access
3. Recreate service principal if needed

#### ❌ "Insufficient permissions" Errors  
**Cause:** Service principal lacks required permissions  
**Solution:**
1. Ensure Contributor role is assigned to correct scope
2. Check subscription-level permissions
3. Verify resource provider registrations

#### ❌ "Database connection failed" Errors
**Cause:** Incorrect database password or configuration  
**Solution:**
1. Verify POSTGRES_ADMIN_PASSWORD complexity requirements
2. Check for special characters that need escaping
3. Test database connectivity manually

### Validation Commands

```bash
# Test Azure authentication
az account show

# Validate service principal
az ad sp show --id <ARM_CLIENT_ID>

# Test database password complexity
# (Should be 12+ characters with mixed case, numbers, symbols)

# Check GitHub secrets (in repository)
# Go to Settings → Secrets and variables → Actions
```

## 🚀 Next Steps After Adding Secrets

1. **Verify All Secrets Added**
   - Check all 5 required secrets are configured in GitHub
   - Ensure no typos in secret names (case-sensitive)

2. **Test the Pipeline**
   ```bash
   # Push to main branch to trigger full pipeline
   git push origin main
   
   # Monitor pipeline progress
   ./scripts/monitor-pipeline.sh
   ```

3. **Validate Deployment**
   ```bash
   # Run comprehensive deployment validation
   ./scripts/validate-deployment.sh
   
   # Check application health
   ./scripts/check-app-status.sh
   ```

4. **Security Verification**
   ```bash
   # Run local security scan
   ./scripts/test-trivy-scan.sh
   
   # Check GitHub Security tab after pipeline completion
   # Repository → Security → Code scanning alerts
   ```

## 📚 Additional Resources

- **[Security Scanning Guide](docs/security-scanning-guide.md)** - Comprehensive security documentation
- **[Manual Testing Guide](docs/manual-testing-guide.md)** - Step-by-step deployment testing
- **[CI/CD Deployment Fixes](docs/ci-cd-deployment-fixes.md)** - Pipeline troubleshooting
- **[Database Migration Troubleshooting](docs/database-migration-troubleshooting.md)** - Database issue resolution

## 🆘 Support

If you encounter issues:
1. **Check logs** in GitHub Actions workflow runs
2. **Review documentation** in the `docs/` directory
3. **Run diagnostic scripts** in the `scripts/` directory
4. **Validate secrets** format and permissions

---

**🔒 Security Note**: Keep all secrets confidential and rotate them regularly. Never share secrets in documentation, chat, or version control.

**✅ Ready for Production**: Once all secrets are configured, your ZoneAPI pipeline includes comprehensive security scanning, automated deployment, and monitoring capabilities. 