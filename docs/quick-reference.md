# ZoneAPI Database Migration - Quick Reference

## 🚨 Emergency Debugging Commands

### Check Pipeline Status
```bash
# Check migration job
kubectl get jobs --namespace=zoneapi -l app.kubernetes.io/component=migration

# Get migration logs
kubectl logs --namespace=zoneapi -l app.kubernetes.io/component=migration --tail=100

# Check pod status
kubectl get pods --namespace=zoneapi

# Check recent events
kubectl get events --namespace=zoneapi --sort-by='.lastTimestamp' | tail -20
```

### Test Database Connection
```bash
# Quick connection test
kubectl run test-db --image=postgres:15-alpine --restart=Never --rm -i --tty \
  --env="PGPASSWORD=YOUR_PASSWORD" \
  --namespace=zoneapi \
  -- psql -h psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com -U postgres -d zone -c "SELECT current_database();"

# Local connection test (requires PostgreSQL client)
./scripts/test-db-connection.sh psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com YOUR_PASSWORD
```

### Check ACR Authentication
```bash
# Check image pull secret
kubectl get secret acr-secret --namespace=zoneapi
kubectl describe secret acr-secret --namespace=zoneapi

# Check ACR login
az acr login --name acrzoenapidevlb46ixxh
```

## 🔧 Key Configuration Files

### Database Connection String Format
```
Host=psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com;Port=5432;Database=zone;Username=postgres;Password=YOUR_PASSWORD;Command Timeout=300;
```

### Required Azure Permissions
```bash
# Grant service principal permissions
az role assignment create \
  --assignee c49c3b05-14bb-4446-9f8e-7c252add74ba \
  --role "User Access Administrator" \
  --scope /subscriptions/a4356e2f-4f1a-405b-95ab-0eaacea61ceb
```

### Terraform Key Resources
```hcl
# PostgreSQL with public access
resource "azurerm_postgresql_flexible_server" "postgres" {
  public_network_access_enabled = true
  authentication {
    password_auth_enabled = true
  }
}

# ACR role assignment
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
```

## 📊 Current Infrastructure Details

| Component | Value |
|-----------|--------|
| **Database Host** | `psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com` |
| **Database Name** | `zone` |
| **Database User** | `postgres` |
| **Database Port** | `5432` |
| **ACR Name** | `acrzoenapidevlb46ixxh` |
| **Service Principal** | `c49c3b05-14bb-4446-9f8e-7c252add74ba` |
| **Subscription** | `a4356e2f-4f1a-405b-95ab-0eaacea61ceb` |

## 🎯 Common Issues & Solutions

### Issue: ImagePullBackOff
**Solution:**
```bash
# Create image pull secret
kubectl create secret docker-registry acr-secret \
  --docker-server=acrzoenapidevlb46ixxh.azurecr.io \
  --docker-username=acrzoenapidevlb46ixxh \
  --docker-password=YOUR_ACR_PASSWORD \
  --namespace=zoneapi
```

### Issue: Migration Timeout
**Check:**
1. Database connectivity: `pg_isready -h HOST -p 5432 -U postgres`
2. Migration job logs: `kubectl logs job/zoneapi-migration-latest -n zoneapi`
3. Timeout settings in `values.yaml`: `migration.timeout: 120`

### Issue: Connection Refused
**Check:**
1. Firewall rules: All IPs allowed (0.0.0.0-255.255.255.255)
2. Public access: `public_network_access_enabled = true`
3. DNS resolution: `nslookup psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com`

### Issue: Authentication Failed
**Check:**
1. Password in GitHub secrets: `POSTGRES_ADMIN_PASSWORD`
2. Connection string format: Use `Command Timeout` not `CommandTimeout`
3. Database user exists: `postgres` (default admin user)

## 🚀 Deployment Commands

### Manual Deployment
```bash
# Deploy with debug enabled
helm upgrade --install zoneapi ./charts/zoneapi \
  --namespace zoneapi \
  --set image.repository=acrzoenapidevlb46ixxh.azurecr.io/zoneapi \
  --set image.tag=latest \
  --set database.host=psql-zoneapi-dev-lb46ixxh.postgres.database.azure.com \
  --set database.password=YOUR_PASSWORD \
  --set debug.enabled=true \
  --set migration.timeout=120 \
  --debug --wait --timeout=5m
```

### Force Migration Re-run
```bash
# Delete existing migration job
kubectl delete job -l app.kubernetes.io/component=migration -n zoneapi

# Trigger Helm upgrade
helm upgrade zoneapi ./charts/zoneapi --namespace zoneapi --reuse-values
```

## 📝 Monitoring Dashboard

### Health Check URLs
- **Application Health**: `http://INGRESS_HOST/health`
- **Database Connection**: Use test script or connection pod

### Key Metrics to Monitor
- Migration job completion time (should be < 2 minutes)
- Pod readiness time (should be < 30 seconds after migration)
- Database connection latency
- ACR image pull success rate

## 🔄 CI/CD Pipeline Triggers

### Manual Pipeline Run
1. Push any commit to `master` branch
2. Ensure GitHub secrets are configured:
   - `AZURE_CREDENTIALS`
   - `ARM_CLIENT_ID`
   - `ARM_CLIENT_SECRET`
   - `ARM_SUBSCRIPTION_ID`
   - `ARM_TENANT_ID`
   - `POSTGRES_ADMIN_PASSWORD`

### Pipeline Stages
1. **Build & Test** (2-3 minutes)
2. **Infrastructure Deploy** (3-5 minutes)
3. **Docker Build & Push** (2-4 minutes)
4. **Connection Test** (30 seconds)
5. **Application Deploy** (2-3 minutes)
6. **Migration Execute** (30-120 seconds)
7. **Health Check** (30 seconds)

**Total Expected Time**: 10-15 minutes

## 📚 Additional Resources

- **Full Troubleshooting Guide**: `docs/database-migration-troubleshooting.md`
- **Terraform State Management**: `docs/terraform-state-management.md`
- **Manual Test Script**: `scripts/test-db-connection.sh`
- **Postman Collection**: `zoneAPI.postman_collection.json` 