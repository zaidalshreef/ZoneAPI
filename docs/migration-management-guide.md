# Database Migration Management Guide

## Overview

This guide explains how to manage database migrations in the ZoneAPI project. The system uses Entity Framework Core migrations with an "efbundle" approach for containerized deployment.

## 🚀 Quick Reference

### ✅ Migration Successfully Completed

If you see a job with status `Complete` like:
```
zoneapi-migration-migration-latest-1752681431   Complete   1/1           8s         70s
```

Your migration was successful! The database schema has been updated.

### ❌ Migration Failed

If you see jobs with status `Failed` or authentication errors:
```
28P01: password authentication failed for user "postgres"
```

Follow the troubleshooting steps below.

## 🛠️ Troubleshooting

### 1. Authentication Issues

**Problem**: `password authentication failed for user "postgres"`

**Solution**: 
1. Get the correct password from Terraform:
   ```bash
   cd terraform
   terraform output postgres_connection_string
   ```

2. Update GitHub secret `POSTGRES_ADMIN_PASSWORD` with the correct password

3. Re-run the pipeline

### 2. Clean Environment

**Problem**: Old failed migration jobs interfering with new ones

**Solution**: The pipeline now automatically cleans up old jobs, but you can also clean manually:

```bash
# From your local machine (if connected to AKS)
chmod +x ./scripts/cleanup-migration-jobs.sh
./scripts/cleanup-migration-jobs.sh zoneapi true

# Or clean specific namespace
./scripts/cleanup-migration-jobs.sh my-namespace true
```

### 3. Check Migration Status

**View current migration jobs:**
```bash
kubectl get jobs -n zoneapi -l app.kubernetes.io/component=migration
```

**View migration pods:**
```bash
kubectl get pods -n zoneapi -l app.kubernetes.io/component=migration
```

**Check logs of latest migration:**
```bash
# Get the latest job name
latest_job=$(kubectl get jobs -n zoneapi -l app.kubernetes.io/component=migration --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

# View logs
kubectl logs -l job-name="$latest_job" -n zoneapi
```

## 🔧 How It Works

### 1. Pipeline Flow

1. **Infrastructure Deployment**: Creates AKS, PostgreSQL, ACR
2. **Docker Build**: Builds application image with efbundle
3. **Migration Job**: 
   - ✅ **Cleanup**: Removes old failed migration jobs
   - ✅ **Connection Test**: Verifies database connectivity  
   - ✅ **Migration**: Runs efbundle migration
   - ✅ **Verification**: Confirms migration success
4. **Application Deployment**: Deploys the application

### 2. Migration Job Template

The migration job is created with:
- **Unique name**: `zoneapi-migration-migration-latest-{timestamp}`
- **Direct password**: Password passed directly from GitHub secrets
- **Timeout**: 10 minutes with backoff limit of 3
- **Environment**: Uses the same image as the application

### 3. Password Flow

```
GitHub Secret (POSTGRES_ADMIN_PASSWORD) 
    ↓
Environment Variable (DB_PASSWORD)
    ↓
Helm Values (database.password)
    ↓
Migration Job Container (direct connection string)
```

## 📋 Environment Variables

The migration process uses these environment variables:

| Variable | Source | Purpose |
|----------|--------|---------|
| `ACR_LOGIN_SERVER` | Terraform output | Container registry |
| `DATABASE_HOST` | Terraform output | PostgreSQL server FQDN |
| `DB_PASSWORD` | GitHub secret | Database password |
| `IMAGE_TAG` | Build process | Docker image tag |
| `NAMESPACE` | Static | Kubernetes namespace |

## 🎯 Best Practices

### 1. Clean Environment Strategy

- **Automatic cleanup**: Pipeline cleans old jobs before new migrations
- **Force cleanup**: Use `force=true` for stuck resources
- **Manual cleanup**: Available via dedicated script

### 2. Timeout Management  

- **Job timeout**: 10 minutes (600 seconds)
- **Step timeout**: 1 minute for quick feedback
- **Backoff limit**: 3 retries for transient failures

### 3. Monitoring

- **Real-time monitoring**: Pipeline shows live migration status
- **Detailed logs**: Full EF Core migration logs captured
- **Post-migration verification**: Database state validation

## 🚨 Common Issues

### Issue 1: Job Already Exists
**Error**: Job name already exists
**Cause**: Previous job with same name still present
**Fix**: Automatic cleanup in pipeline resolves this

### Issue 2: Image Pull Errors
**Error**: Cannot pull container image
**Cause**: ACR authentication or image doesn't exist
**Fix**: Check Docker build step completed successfully

### Issue 3: Database Connection Timeout
**Error**: Connection timeout to PostgreSQL
**Cause**: Network issues or database not ready
**Fix**: Azure PostgreSQL firewall rules allow AKS access

### Issue 4: Migration Already Applied
**Warning**: Migration already exists in database
**Cause**: Migration previously applied successfully
**Result**: EF Core skips already applied migrations (normal behavior)

## 🎛️ Manual Operations

### Force Delete All Migration Resources

```bash
# Nuclear option - removes everything migration-related
kubectl delete jobs -n zoneapi -l app.kubernetes.io/component=migration --force --grace-period=0
kubectl delete pods -n zoneapi -l app.kubernetes.io/component=migration --force --grace-period=0
```

### Test Database Connection

```bash
# Test connection with current password
kubectl run db-test --image=postgres:15-alpine --rm -i --restart=Never \
  --namespace=zoneapi \
  --env="PGPASSWORD=YOUR_PASSWORD" \
  -- psql -h POSTGRES_HOST -U postgres -d zone -c "SELECT version();"
```

### Check Migration History

```bash
# View applied migrations
kubectl run migration-history --image=postgres:15-alpine --rm -i --restart=Never \
  --namespace=zoneapi \
  --env="PGPASSWORD=YOUR_PASSWORD" \
  -- psql -h POSTGRES_HOST -U postgres -d zone \
  -c "SELECT migration_id, product_version FROM __EFMigrationsHistory ORDER BY migration_id;"
```

## 📊 Success Indicators

✅ **Migration Successful**:
- Job status: `Complete`
- Pod status: `Succeeded` 
- Logs show: `Done.` at the end
- No error messages in logs

❌ **Migration Failed**:
- Job status: `Failed`
- Pod status: `Error`
- Error messages in logs
- May need manual intervention

## 🔄 Pipeline Integration

The migration is fully integrated with the CI/CD pipeline:

1. **Automatic trigger**: Runs on push to main/master
2. **Dependency management**: Waits for infrastructure and image build
3. **Clean environment**: Automatic cleanup of old resources
4. **Fast feedback**: 1-minute timeouts for quick error detection
5. **Detailed reporting**: Comprehensive logs and status reporting

## 📞 Support

For issues not covered in this guide:

1. Check the pipeline logs in GitHub Actions
2. Run the debug scripts in the `scripts/` directory
3. Review the Helm charts in `charts/zoneapi/`
4. Check Azure resources in the Azure portal 