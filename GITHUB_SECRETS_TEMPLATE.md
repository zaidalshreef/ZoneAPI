# GitHub Secrets Configuration Template

## Required GitHub Secrets

Configure these secrets in your GitHub repository:

### Azure Authentication Secrets

```
ARM_CLIENT_ID = <your-service-principal-client-id>
ARM_CLIENT_SECRET = <your-service-principal-client-secret>
ARM_SUBSCRIPTION_ID = <your-azure-subscription-id>
ARM_TENANT_ID = <your-azure-tenant-id>
```

### Azure Credentials JSON

```json
AZURE_CREDENTIALS = {
  "appId": "<your-service-principal-client-id>",
  "displayName": "<your-service-principal-display-name>",
  "password": "<your-service-principal-client-secret>",
  "tenant": "<your-azure-tenant-id>"
}
```

### Database Secret

```
POSTGRES_ADMIN_PASSWORD = <your-secure-database-password>
```

## How to Add Secrets to GitHub

1. Go to your repository on GitHub
2. Click on **Settings** tab
3. Click on **Secrets and variables** → **Actions**
4. Click **New repository secret**
5. Add each secret with the exact name and value from your setup script output

## Required Secrets List

- ARM_CLIENT_ID
- ARM_CLIENT_SECRET
- ARM_SUBSCRIPTION_ID
- ARM_TENANT_ID
- AZURE_CREDENTIALS (paste the entire JSON)
- POSTGRES_ADMIN_PASSWORD

## After Adding Secrets

The ACR secrets (ACR_LOGIN_SERVER, ACR_USERNAME, ACR_PASSWORD) will be automatically set after Terraform creates the Azure Container Registry.

## Getting Secret Values

Run the setup script to get the actual values:
```bash
./scripts/setup.sh
```

## Next Steps

1. Add all secrets above to GitHub
2. Push code to main branch
3. Monitor GitHub Actions for deployment
4. Test your deployed application 