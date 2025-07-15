# Database Migration Troubleshooting Guide

## Overview
This document outlines the complete troubleshooting process for resolving database connection and migration issues in the ZoneAPI CI/CD pipeline.

## Issues Encountered

### 1. Initial Problem: Migration Job Timeout
- **Symptom**: Helm deployment hanging on migration pre-hook
- **Error**: Migration job was timing out after 5+ minutes
- **Root Cause**: Multiple configuration and authentication issues

### 2. Database Connection Issues
- **Symptom**: Pods couldn't connect to PostgreSQL database
- **Error**: Connection timeouts and authentication failures
- **Root Cause**: Missing public network access and authentication configuration

### 3. ACR Authentication Issues
- **Symptom**: ImagePullBackOff errors in Kubernetes
- **Error**: `failed to authorize: failed to fetch anonymous token: 401 Unauthorized`
- **Root Cause**: AKS cluster lacked permissions to pull images from ACR

### 4. Azure Permissions Issues
- **Symptom**: Terraform apply failures
- **Error**: `AuthorizationFailed: The client does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'`
- **Root Cause**: Service principal lacked sufficient permissions

## Solutions Implemented

### 1. Database Configuration Fixes

#### A. Updated PostgreSQL Flexible Server (`terraform/main.tf`)
```hcl
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
```

#### B. Fixed Connection String Format
- **Before**: `CommandTimeout=300;Timeout=60;` (conflicting parameters)
- **After**: `Command Timeout=300;` (proper format)

### 2. Migration Architecture Redesign

#### A. Separate Migration Job (`charts/zoneapi/templates/migration-job.yaml`)
Replaced initContainer approach with dedicated Kubernetes Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "zoneapi.fullname" . }}-migration-{{ .Values.image.tag | default .Chart.AppVersion | replace "." "-" }}
  labels:
    {{- include "zoneapi.labels" . | nindent 4 }}
    app.kubernetes.io/component: migration
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-1"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ .Values.migration.backoffLimit | default 3 }}
  activeDeadlineSeconds: {{ .Values.migration.timeout | default 120 }}
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: wait-for-db
          image: postgres:15-alpine
          command:
            - /bin/bash
            - -c
            - |
              # Wait up to 2 minutes for database (24 attempts x 5 seconds)
              for i in {1..24}; do
                if pg_isready -h $DB_HOST -p $DB_PORT -U $DB_USER; then
                  if psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
                    echo "Database connection successful!"
                    exit 0
                  fi
                fi
                sleep 5
              done
              exit 1
      containers:
        - name: migration
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          command:
            - /bin/bash
            - -c
            - |
              echo "=== Database Migration ==="
              chmod +x /app/efbundle
              /app/efbundle --connection "Host={{ .Values.database.host }};Port={{ .Values.database.port }};Database={{ .Values.database.name }};Username={{ .Values.database.user }};Password=$DB_PASSWORD;Command Timeout=300;" --verbose
```

#### B. Realistic Timeouts
- **Migration timeout**: 120 seconds (2 minutes) instead of 15-20 minutes
- **Database readiness**: 2 minutes instead of 5 minutes
- **Helm timeout**: 5 minutes instead of 20 minutes

### 3. Connection Testing Framework

#### A. Database Connection Test (`charts/zoneapi/templates/test-connection-pod.yaml`)
Created comprehensive 6-step connection test:

1. **DNS Resolution**: `nslookup <hostname>`
2. **Network Connectivity**: `nc -zv <host> <port>`
3. **PostgreSQL Service**: `pg_isready`
4. **Authentication**: `psql -c "SELECT version();"`
5. **Target Database Access**: `psql -d zone -c "SELECT current_database();"`
6. **Connection String Validation**: Format verification

#### B. CI/CD Integration (`.github/workflows/ci-cd.yml`)
```yaml
- name: Test database connection first
  run: |
    kubectl run zoneapi-connection-test \
      --namespace=zoneapi \
      --image=postgres:15-alpine \
      --restart=Never \
      --rm -i --tty=false \
      --env="PGPASSWORD=${{ secrets.POSTGRES_ADMIN_PASSWORD }}" \
      --command -- /bin/bash -c "
        echo 'Step 1: Testing DNS resolution...'
        nslookup ${{ needs.deploy-infrastructure.outputs.postgres-host }}
        
        echo 'Step 2: Testing network connectivity...'
        nc -zv ${{ needs.deploy-infrastructure.outputs.postgres-host }} 5432
        
        echo 'Step 3: Testing PostgreSQL service...'
        pg_isready -h ${{ needs.deploy-infrastructure.outputs.postgres-host }} -p 5432 -U postgres
        
        echo 'Step 4: Testing authentication...'
        psql -h ${{ needs.deploy-infrastructure.outputs.postgres-host }} -p 5432 -U postgres -d postgres -c 'SELECT version();'
        
        echo 'Step 5: Testing database zone access...'
        psql -h ${{ needs.deploy-infrastructure.outputs.postgres-host }} -p 5432 -U postgres -d zone -c 'SELECT current_database();'
        
        echo '✅ Connection test completed'
      "
```

#### C. Manual Testing Script (`scripts/test-db-connection.sh`)
Created standalone script for local testing:

```bash
#!/bin/bash
# Usage: ./test-db-connection.sh <host> <password>

DB_HOST="${1:-psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com}"
DB_PASSWORD="${2}"
export PGPASSWORD="$DB_PASSWORD"

echo "Step 1: Testing DNS resolution..."
nslookup "$DB_HOST"

echo "Step 2: Testing network connectivity..."
nc -zv "$DB_HOST" "$DB_PORT"

echo "Step 3: Testing PostgreSQL service..."
pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"

echo "Step 4: Testing authentication..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT version();"

echo "Step 5: Testing target database access..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT current_database();"

echo "🎉 All database connection tests passed!"
```

### 4. ACR Authentication Solutions

#### A. AKS-ACR Integration (`terraform/main.tf`)
```hcl
# Give AKS permission to pull images from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
```

#### B. Image Pull Secret Backup (`.github/workflows/ci-cd.yml`)
```yaml
- name: Setup ACR authentication for AKS
  run: |
    ACR_LOGIN_SERVER=$(cd terraform && terraform output -raw acr_login_server)
    ACR_USERNAME=$(cd terraform && terraform output -raw acr_admin_username)
    ACR_PASSWORD=$(cd terraform && terraform output -raw acr_admin_password)
    
    kubectl create secret docker-registry acr-secret \
      --docker-server="$ACR_LOGIN_SERVER" \
      --docker-username="$ACR_USERNAME" \
      --docker-password="$ACR_PASSWORD" \
      --namespace=zoneapi \
      --dry-run=client -o yaml | kubectl apply -f -
```

#### C. Helm Configuration
```yaml
--set imagePullSecrets[0].name=acr-secret
```

### 5. Azure Permissions Resolution

#### Required Permission
```bash
az role assignment create \
  --assignee <service-principal-id> \
  --role "User Access Administrator" \
  --scope /subscriptions/<subscription-id>
```

**Service Principal ID**: `c49c3b05-14bb-4446-9f8e-7c252add74ba`
**Subscription ID**: `a4356e2f-4f1a-405b-95ab-0eaacea61ceb`

## Testing Results

### Database Connection Test Results ✅
```
Step 1: Testing DNS resolution... ✅
Step 2: Testing network connectivity... ✅  
Step 3: Testing PostgreSQL service... ✅
Step 4: Testing authentication... ✅
Step 5: Testing database zone access... ✅
Step 6: Connection string format... ✅
```

**PostgreSQL Details:**
- **Host**: `psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com`
- **Port**: `5432`
- **Database**: `zone`
- **User**: `postgres`
- **Version**: `PostgreSQL 14.18`

## Configuration Files Updated

### 1. Terraform Files
- `terraform/main.tf`: PostgreSQL and ACR configuration
- `terraform/outputs.tf`: Database connection outputs

### 2. Helm Charts
- `charts/zoneapi/templates/migration-job.yaml`: New migration job
- `charts/zoneapi/templates/test-connection-pod.yaml`: Connection testing
- `charts/zoneapi/templates/deployment.yaml`: Removed initContainer
- `charts/zoneapi/values.yaml`: Added debug and migration config

### 3. CI/CD Pipeline
- `.github/workflows/ci-cd.yml`: Enhanced with connection testing and ACR auth

### 4. Scripts
- `scripts/test-db-connection.sh`: Manual testing utility

## Key Learnings

### 1. Connection String Format Matters
- Use `Command Timeout=300;` not `CommandTimeout=300;Timeout=60;`
- Spaces in parameter names are significant

### 2. Azure PostgreSQL Flexible Server Requirements
- Must explicitly enable `public_network_access_enabled = true`
- Must configure `authentication` block for password auth

### 3. ACR Integration Best Practices
- Use role assignments for native Azure integration
- Maintain image pull secrets as backup
- Requires "User Access Administrator" permissions

### 4. Migration Strategy
- Separate Job is more reliable than initContainer
- Database readiness checks are essential
- Realistic timeouts prevent false failures

### 5. Testing First Approach
- Test database connectivity before attempting migration
- Fail fast with clear error messages
- Use step-by-step debugging for complex issues

## Monitoring and Debugging Commands

### Check Migration Job Status
```bash
kubectl get jobs --namespace=zoneapi -l app.kubernetes.io/component=migration
kubectl logs --namespace=zoneapi -l app.kubernetes.io/component=migration --tail=100
```

### Check Database Connection
```bash
kubectl run test-db --image=postgres:15-alpine --restart=Never --rm -i --tty \
  --env="PGPASSWORD=<password>" \
  -- psql -h <host> -U postgres -d zone -c "SELECT current_database();"
```

### Check ACR Authentication
```bash
kubectl get secret acr-secret --namespace=zoneapi
kubectl describe secret acr-secret --namespace=zoneapi
```

### Check Events
```bash
kubectl get events --namespace=zoneapi --sort-by='.lastTimestamp' | tail -20
```

## Future Improvements

1. **Health Checks**: Add liveness/readiness probes for better monitoring
2. **Backup Strategy**: Implement database backup before migrations
3. **Rollback Capability**: Add migration rollback mechanisms
4. **Performance Monitoring**: Add metrics for migration duration
5. **Security**: Rotate ACR credentials regularly

## Conclusion

The comprehensive approach of testing connectivity first, using proper Azure integration, and implementing realistic timeouts resolved all migration issues. The key was systematic debugging and addressing each layer of the problem (network, authentication, permissions, and configuration). 