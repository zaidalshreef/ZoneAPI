# Manual Deployment (No Helm)

This directory contains Kubernetes YAML files and scripts for deploying ZoneAPI manually without Helm. This approach is useful for troubleshooting Helm-related issues and understanding the underlying Kubernetes resources.

## Files Overview

- `01-secret.yaml` - Database credentials secret
- `02-migration-job.yaml` - Database migration job
- `03-deployment.yaml` - Application deployment
- `04-service.yaml` - Application service
- `../scripts/manual-deploy.sh` - Deployment automation script

## Usage

### Option 1: Using the Automated Script (Recommended)

The `scripts/manual-deploy.sh` script automates the entire manual deployment process:

```bash
# Check secrets and current state only
export ACR_REGISTRY=your-registry.azurecr.io
export DB_HOST=your-postgres.postgres.database.azure.com
export POSTGRES_ADMIN_PASSWORD=your-password
./scripts/manual-deploy.sh check

# Full deployment
./scripts/manual-deploy.sh deploy

# Clean up all resources
./scripts/manual-deploy.sh clean
```

### Option 2: Using GitHub Actions Workflow

Run the "Manual Deployment Test" workflow from the GitHub Actions tab:

1. Go to Actions → Manual Deployment Test (No Helm)
2. Click "Run workflow"
3. Choose options:
   - **Clean before deploy**: Remove existing resources first
   - **Check secrets only**: Only check cluster state without deploying

### Option 3: Manual kubectl Commands

If you need to deploy manually step by step:

1. **Prepare environment variables:**
   ```bash
   export ACR_REGISTRY=your-registry.azurecr.io
   export DB_HOST=your-postgres.postgres.database.azure.com
   export POSTGRES_ADMIN_PASSWORD=your-password
   ```

2. **Create temporary deployment files:**
   ```bash
   mkdir -p manual-deploy/temp
   
   # Replace placeholders in each file
   sed -e "s|ACR_REGISTRY_PLACEHOLDER|$ACR_REGISTRY|g" \
       -e "s|DB_HOST_PLACEHOLDER|$DB_HOST|g" \
       manual-deploy/01-secret.yaml > manual-deploy/temp/01-secret.yaml
   
   sed -e "s|ACR_REGISTRY_PLACEHOLDER|$ACR_REGISTRY|g" \
       -e "s|DB_HOST_PLACEHOLDER|$DB_HOST|g" \
       manual-deploy/02-migration-job.yaml > manual-deploy/temp/02-migration-job.yaml
   
   sed -e "s|ACR_REGISTRY_PLACEHOLDER|$ACR_REGISTRY|g" \
       -e "s|DB_HOST_PLACEHOLDER|$DB_HOST|g" \
       manual-deploy/03-deployment.yaml > manual-deploy/temp/03-deployment.yaml
   
   cp manual-deploy/04-service.yaml manual-deploy/temp/04-service.yaml
   ```

3. **Update secret with correct password:**
   ```bash
   kubectl create secret generic zoneapi-db-secret \
     --from-literal=password="$POSTGRES_ADMIN_PASSWORD" \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

4. **Deploy resources in order:**
   ```bash
   kubectl apply -f manual-deploy/temp/02-migration-job.yaml
   kubectl apply -f manual-deploy/temp/03-deployment.yaml
   kubectl apply -f manual-deploy/temp/04-service.yaml
   ```

5. **Monitor deployment:**
   ```bash
   # Watch migration job
   kubectl get job zoneapi-migration-latest -w
   kubectl logs -f job/zoneapi-migration-latest
   
   # Watch application deployment
   kubectl rollout status deployment/zoneapi
   kubectl get pods -l app.kubernetes.io/name=zoneapi -w
   ```

## Troubleshooting

### Check Current Secrets

```bash
# List all secrets
kubectl get secrets

# Check if zoneapi-db-secret exists
kubectl get secret zoneapi-db-secret

# View secret details
kubectl describe secret zoneapi-db-secret

# Check password key (will show base64 encoded value)
kubectl get secret zoneapi-db-secret -o jsonpath='{.data.password}' | base64 -d
```

### Debug Migration Issues

```bash
# Check migration job status
kubectl describe job zoneapi-migration-latest

# View migration logs
kubectl logs -l job-name=zoneapi-migration-latest

# Check for failed pods
kubectl get pods -l job-name=zoneapi-migration-latest
kubectl describe pod <migration-pod-name>
```

### Debug Application Issues

```bash
# Check deployment status
kubectl describe deployment zoneapi

# View application logs
kubectl logs -l app.kubernetes.io/name=zoneapi -f

# Check pod details
kubectl get pods -l app.kubernetes.io/name=zoneapi
kubectl describe pod <app-pod-name>

# Test connectivity to database
kubectl run test-db --rm -it --image=postgres:15-alpine -- psql -h $DB_HOST -U postgres -d zone
```

### Test Application

```bash
# Port forward to test locally
kubectl port-forward service/zoneapi 8080:8080

# Test health endpoint
curl http://localhost:8080/health

# Test API endpoints
curl http://localhost:8080/api/doctors
curl http://localhost:8080/api/patients
curl http://localhost:8080/api/appointments
```

## Differences from Helm Deployment

This manual approach differs from Helm in several ways:

1. **Static Resource Names**: No templating, resources have fixed names
2. **No Version Management**: Resources aren't tracked as a single release
3. **Manual Updates**: No automatic upgrade/rollback capabilities
4. **Simplified Labels**: Basic Kubernetes labels instead of Helm-generated ones
5. **Direct Secret Management**: Secrets created directly, not through Helm

## Comparison with Helm Issues

If manual deployment works but Helm deployment fails, the issue is likely:

1. **Template Rendering**: Helm templates have syntax errors or incorrect values
2. **Secret Name Mismatches**: Helm generates different secret names than expected
3. **Value Interpolation**: Values not being passed correctly to templates
4. **Release Management**: Existing Helm releases conflicting with new deployments
5. **Namespace Issues**: Helm deploying to wrong namespace or with incorrect RBAC

## Cleanup

To remove all manually deployed resources:

```bash
./scripts/manual-deploy.sh clean
```

Or manually:

```bash
kubectl delete deployment zoneapi
kubectl delete service zoneapi
kubectl delete job zoneapi-migration-latest
kubectl delete secret zoneapi-db-secret
```

## Next Steps

After confirming manual deployment works:

1. Compare working manual YAML with Helm template output
2. Identify differences in resource names, labels, or configuration
3. Fix Helm templates to match working manual deployment
4. Test Helm deployment with corrected templates
5. Migrate back to Helm for production use 