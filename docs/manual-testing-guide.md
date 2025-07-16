# Manual Testing Guide for ZoneAPI CI/CD Pipeline

This guide explains how to manually test each step of the CI/CD pipeline before running it automatically. By testing manually first, you can identify and fix issues, ensuring the automated pipeline will work correctly.

## 🎯 Overview

The approach is simple:
1. **Test manually first** - Run each step using kubectl, helm, and az CLI
2. **Fix any issues** - Address configuration problems, missing secrets, etc.
3. **Run automated pipeline** - The pipeline will now automate what you've tested manually

## 📋 Prerequisites

Before starting, ensure you have:

- [x] Azure CLI installed and logged in (`az login`)
- [x] kubectl installed and configured
- [x] Helm v3 installed
- [x] Docker (if building images locally)
- [x] Access to your Azure subscription
- [x] Infrastructure deployed via Terraform

## 🚀 Quick Start

### Step 1: Run the Manual Test Script

```bash
# Navigate to your project directory
cd /path/to/your/ZoneAPI

# Run the comprehensive manual test
./scripts/test-manual-deployment.sh
```

The script will:
- Check prerequisites
- Get configuration from Terraform or prompt for input
- Connect to your AKS cluster
- Test each pipeline step manually
- Provide detailed feedback and recommendations

### Step 2: Fix Any Issues Found

If the manual test finds issues, follow the troubleshooting sections below.

### Step 3: Run the Automated Pipeline

Once manual testing passes, push your changes to trigger the automated pipeline:

```bash
git add .
git commit -m "Fix CI/CD pipeline configuration"
git push origin main
```

## 🔧 Manual Step-by-Step Testing

### 1. Infrastructure Verification

```bash
# Check your Terraform state
cd terraform
terraform output

# Verify key outputs exist:
# - resource_group_name
# - aks_cluster_name  
# - acr_login_server
# - postgres_server_fqdn
```

### 2. Connect to AKS

```bash
# Get your resource group and cluster name from Terraform
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
AKS_CLUSTER=$(terraform output -raw aks_cluster_name)

# Connect to AKS
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --overwrite-existing

# Verify connection
kubectl get nodes
kubectl cluster-info
```

### 3. Create Namespace and Secrets

```bash
NAMESPACE="zoneapi"

# Create namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create database secret
DB_PASSWORD="your-db-password"
kubectl create secret generic zoneapi-db-secret \
    --namespace="$NAMESPACE" \
    --from-literal=password="$DB_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create ACR secret
ACR_NAME="your-acr-name"
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query passwords[0].value --output tsv)

kubectl create secret docker-registry acr-secret \
    --namespace="$NAMESPACE" \
    --docker-server="$ACR_NAME.azurecr.io" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

# Verify secrets
kubectl get secrets -n "$NAMESPACE"
```

### 4. Test Database Connectivity

```bash
# Test database connection from within Kubernetes
kubectl run db-test --image=postgres:15-alpine --rm -i --restart=Never --namespace="$NAMESPACE" \
    --overrides='{
      "spec": {
        "containers": [{
          "name": "db-test",
          "image": "postgres:15-alpine",
          "env": [{
            "name": "PGPASSWORD",
            "valueFrom": {
              "secretKeyRef": {
                "name": "zoneapi-db-secret",
                "key": "password"
              }
            }
          }],
          "command": ["psql"],
          "args": ["-h", "your-db-host.postgres.database.azure.com", "-U", "postgres", "-d", "zone", "-c", "SELECT version();"]
        }]
      }
    }' --timeout=60s
```

### 5. Test ACR Image Pull

```bash
# Test that your image can be pulled
IMAGE_TAG="latest"
kubectl run acr-test --image="$ACR_NAME.azurecr.io/zoneapi:$IMAGE_TAG" \
    --rm -i --restart=Never --namespace="$NAMESPACE" \
    --overrides='{
      "spec": {
        "imagePullSecrets": [{"name": "acr-secret"}],
        "containers": [{
          "name": "test",
          "image": "'$ACR_NAME'.azurecr.io/zoneapi:'$IMAGE_TAG'",
          "command": ["/bin/sh", "-c", "echo Image pull successful; exit 0"]
        }]
      }
    }' --timeout=60s
```

### 6. Run Migration

```bash
# Deploy migration job using Helm
helm upgrade --install zoneapi-migration ./charts/zoneapi \
    --namespace "$NAMESPACE" \
    --set migration.enabled=true \
    --set image.repository="$ACR_NAME.azurecr.io/zoneapi" \
    --set image.tag="$IMAGE_TAG" \
    --set imagePullSecrets[0].name=acr-secret \
    --set database.host="your-db-host.postgres.database.azure.com" \
    --set database.password="$DB_PASSWORD" \
    --wait --timeout=5m

# Monitor migration
kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration -w

# Check migration logs
MIGRATION_JOB=$(kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration -o jsonpath='{.items[0].metadata.name}')
kubectl logs -l job-name="$MIGRATION_JOB" -n "$NAMESPACE"
```

### 7. Deploy Application

```bash
# Deploy application
helm upgrade --install zoneapi ./charts/zoneapi \
    --namespace "$NAMESPACE" \
    --set migration.enabled=false \
    --set image.repository="$ACR_NAME.azurecr.io/zoneapi" \
    --set image.tag="$IMAGE_TAG" \
    --set imagePullSecrets[0].name=acr-secret \
    --set database.host="your-db-host.postgres.database.azure.com" \
    --set database.password="$DB_PASSWORD" \
    --set livenessProbe.enabled=true \
    --set readinessProbe.enabled=true \
    --wait --timeout=5m

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zoneapi -n "$NAMESPACE" --timeout=300s

# Check pod status
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi
```

### 8. Test Application Health

```bash
# Get application pod
APP_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=zoneapi -o jsonpath='{.items[0].metadata.name}')

# Test health endpoint
kubectl exec -n "$NAMESPACE" "$APP_POD" -- curl -f http://localhost:8080/health

# Test API endpoints
kubectl exec -n "$NAMESPACE" "$APP_POD" -- curl -f http://localhost:8080/api/doctors

# Check application logs
kubectl logs "$APP_POD" -n "$NAMESPACE" --tail=20
```

## 🐛 Common Issues and Solutions

### Issue 1: Environment Variable Expansion

**Problem**: Database tests fail with "could not translate host name $(DB_HOST)"

**Solution**: Environment variables in kubectl overrides need proper escaping:

```bash
# ❌ Wrong - literal environment variable
kubectl run test --overrides='{
  "spec": {
    "containers": [{
      "command": ["psql", "-h", "$(DB_HOST)"]
    }]
  }
}'

# ✅ Correct - use YAML with proper variable substitution
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: test
    env:
    - name: DB_HOST
      value: "$DB_HOST"
    command: ["psql", "-h", "\$DB_HOST"]
EOF
```

### Issue 2: ACR Authentication

**Problem**: "Unable to retrieve some image pull secrets (acr-secret)"

**Solution**: Ensure ACR secret is created correctly:

```bash
# Verify ACR secret exists
kubectl get secret acr-secret -n "$NAMESPACE" -o yaml

# Recreate if necessary
kubectl delete secret acr-secret -n "$NAMESPACE"
# Then recreate using the commands in step 3
```

### Issue 3: Migration Job Not Found

**Problem**: Pipeline can't find migration jobs

**Solution**: Check job labels and names:

```bash
# Check all jobs
kubectl get jobs -n "$NAMESPACE"

# Check jobs with migration label
kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=migration

# Check job status
kubectl describe job <job-name> -n "$NAMESPACE"
```

### Issue 4: Database Connection Timeout

**Problem**: Database connection tests time out

**Solution**: Check Azure PostgreSQL firewall rules:

```bash
# Verify firewall rule allows AKS traffic
az postgres flexible-server firewall-rule list --resource-group "$RESOURCE_GROUP" --name "$POSTGRES_SERVER"

# Add rule if needed (adjust IP range as needed)
az postgres flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$POSTGRES_SERVER" \
    --rule-name aks-access \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 255.255.255.255
```

## 📊 Monitoring and Debugging

### Real-time Monitoring

```bash
# Watch all resources in namespace
kubectl get all -n "$NAMESPACE" -w

# Watch specific resources
kubectl get pods -n "$NAMESPACE" -w
kubectl get jobs -n "$NAMESPACE" -w

# Follow logs in real-time
kubectl logs -f deployment/zoneapi -n "$NAMESPACE"
```

### Debugging Commands

```bash
# Describe resources for events
kubectl describe pod <pod-name> -n "$NAMESPACE"
kubectl describe job <job-name> -n "$NAMESPACE"

# Get events
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n "$NAMESPACE"
kubectl top nodes

# Debug networking
kubectl exec -n "$NAMESPACE" <pod-name> -- nslookup kubernetes.default
kubectl exec -n "$NAMESPACE" <pod-name> -- curl -I http://kubernetes.default/healthz
```

## ✅ Success Criteria

Your manual testing is successful when:

1. ✅ All prerequisite tools are installed and working
2. ✅ You can connect to AKS cluster
3. ✅ Namespace and secrets are created successfully  
4. ✅ Database connectivity test passes from within Kubernetes
5. ✅ ACR image pull test succeeds
6. ✅ Migration job completes successfully
7. ✅ Application deploys and becomes ready
8. ✅ Health endpoint returns 200 OK
9. ✅ API endpoints are accessible

## 🚀 Next Steps

Once all manual tests pass:

1. **Commit your changes**: All configuration fixes and script updates
2. **Push to trigger pipeline**: The automated pipeline will now work
3. **Monitor the pipeline**: Watch GitHub Actions for automated execution
4. **Document any custom changes**: Update this guide with environment-specific notes

## 📞 Getting Help

If you encounter issues not covered in this guide:

1. Run the comprehensive debug script: `./scripts/debug-migration-status.sh`
2. Check the troubleshooting scripts in `scripts/`
3. Review the logs from manual testing
4. Consult the Azure, Kubernetes, and Helm documentation

Remember: The goal is to get the manual steps working first. Once they work, the automated pipeline will simply repeat the same steps. 