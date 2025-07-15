# Enhanced Migration Monitoring & Debugging Guide

This guide explains how to use the enhanced monitoring and debugging tools added to your ZoneAPI CI/CD pipeline.

## 🚀 What's New

Your CI/CD pipeline now includes comprehensive database connection checks, real-time monitoring, and detailed debugging capabilities to help you troubleshoot migration issues quickly.

## 📊 Enhanced CI/CD Pipeline Features

### 1. Pre-Migration Database Connection Tests
**When it runs:** Before starting any migration
```bash
🔍 PRE-MIGRATION DATABASE CONNECTION TESTS
- Tests database connectivity from GitHub Actions runner
- Verifies PostgreSQL client installation
- Runs comprehensive connection tests
```

### 2. Kubernetes Database Connection Test
**When it runs:** After namespace setup
```bash
🧪 TESTING DATABASE CONNECTION FROM KUBERNETES
- Creates test pod in your Kubernetes cluster
- Tests connectivity from within the cluster network
- Verifies database access with actual credentials
```

### 3. Pre-Migration Database State Check
**When it runs:** Before running migrations
```bash
📊 PRE-MIGRATION DATABASE STATE CHECK
- Checks existing database schema
- Lists current tables
- Shows migration history (if any)
```

### 4. Enhanced Migration Monitoring
**When it runs:** During migration execution
```bash
🚀 RUNNING DATABASE MIGRATION WITH ENHANCED MONITORING
- Real-time monitoring of migration progress
- Detailed logging with timestamps
- Background monitoring process
- Extended timeout (20 minutes)
```

### 5. Detailed Migration Job Analysis
**When it runs:** After migration completion
```bash
🔍 DETAILED MIGRATION JOB ANALYSIS
- Analyzes all migration jobs and pods
- Shows detailed job status and logs
- Identifies failed pods and provides logs
- Reports job completion status
```

### 6. Post-Migration Database Verification
**When it runs:** After successful migration
```bash
📊 POST-MIGRATION DATABASE VERIFICATION
- Verifies database schema post-migration
- Shows migration history
- Confirms all migrations were applied
```

### 7. Comprehensive Troubleshooting (On Failure)
**When it runs:** If any step fails
```bash
🛠️ COMPREHENSIVE MIGRATION TROUBLESHOOTING
- Runs detailed analysis of the entire system
- Provides recommendations
- Shows resource usage and diagnostics
```

## 🔧 Manual Debugging Tools

### 1. Comprehensive Debug Script
Use this to get a complete analysis of your migration status:

```bash
# Run comprehensive analysis
./scripts/debug-migration-status.sh

# Specify custom namespace
./scripts/debug-migration-status.sh my-namespace
```

**What it checks:**
- ✅ Prerequisites (kubectl, cluster connection)
- 🔗 Database connectivity from cluster
- 📋 Migration job analysis
- 💾 Database state and schema
- 🐳 Application pod status
- 🌐 Services and ingress
- 📊 Summary and recommendations

### 2. Enhanced Pipeline Monitor
Monitor your CI/CD pipeline in real-time:

```bash
# Single status check
./scripts/monitor-pipeline.sh

# Continuous monitoring
CONTINUOUS_MONITORING=true ./scripts/monitor-pipeline.sh

# Custom settings
NAMESPACE=zoneapi MONITOR_INTERVAL=15 ./scripts/monitor-pipeline.sh
```

### 3. Enhanced Migration Runner
Run migrations manually with enhanced logging:

```bash
# Set required environment variables
export ACR_LOGIN_SERVER="your-acr.azurecr.io"
export DATABASE_HOST="your-db-host.postgres.database.azure.com"
export DB_PASSWORD="your-password"
export IMAGE_TAG="latest"
export NAMESPACE="zoneapi"

# Run migration
./scripts/run-migration.sh
```

## 📱 Monitoring in GitHub Actions

### View Real-time Logs
1. Go to your GitHub repository
2. Click on "Actions" tab
3. Click on the running workflow
4. Expand the migration job steps to see detailed logs

### Key Log Sections to Watch
1. **🔍 Pre-Migration Tests** - Shows database connectivity
2. **🚀 Migration Execution** - Real-time migration progress
3. **🔍 Migration Analysis** - Detailed job status and logs
4. **📊 Database Verification** - Post-migration validation

## 🚨 Troubleshooting Common Issues

### Migration Job Stuck
```bash
# Check job status
kubectl get jobs -n zoneapi -l app.kubernetes.io/component=migration

# Watch in real-time
kubectl get jobs -n zoneapi -l app.kubernetes.io/component=migration -w

# Get detailed analysis
./scripts/debug-migration-status.sh
```

### Database Connection Issues
```bash
# Test connectivity manually
./scripts/test-db-connection.sh your-db-host.postgres.database.azure.com your-password

# Check from within cluster
kubectl run db-test --image=postgres:15-alpine --rm -i --restart=Never \
  --env="PGPASSWORD=your-password" \
  -- psql -h your-db-host -U postgres -d zone -c "SELECT version();"
```

### Application Not Starting
```bash
# Check pod status
kubectl get pods -n zoneapi -l app.kubernetes.io/name=zoneapi

# View pod logs
kubectl logs -l app.kubernetes.io/name=zoneapi -n zoneapi --tail=50

# Describe pod for events
kubectl describe pod <pod-name> -n zoneapi
```

## 🎯 Best Practices

### 1. Monitor Pipeline Logs
Always check the CI/CD logs for:
- ✅ Database connectivity confirmations
- 📊 Migration progress updates
- ❌ Any error messages or warnings

### 2. Use Debug Script Regularly
Run the debug script to verify your deployment:
```bash
./scripts/debug-migration-status.sh
```

### 3. Check Database State
Verify migrations are applied correctly:
```bash
# Check migration history
kubectl run db-check --image=postgres:15-alpine --rm -i --restart=Never \
  --env="PGPASSWORD=your-password" \
  -- psql -h your-db-host -U postgres -d zone \
  -c "SELECT * FROM __EFMigrationsHistory ORDER BY migration_id;"
```

### 4. Monitor Resource Usage
Keep an eye on resource consumption:
```bash
kubectl top nodes
kubectl top pods -n zoneapi
```

## 📞 Getting Help

### Quick Commands Reference
```bash
# Complete system analysis
./scripts/debug-migration-status.sh

# Watch pipeline progress
./scripts/monitor-pipeline.sh

# Test database connectivity
./scripts/test-db-connection.sh <host> <password>

# Watch migration jobs
kubectl get jobs -n zoneapi -l app.kubernetes.io/component=migration -w

# Follow migration logs
kubectl logs -f -l job-name=<job-name> -n zoneapi

# Check recent events
kubectl get events -n zoneapi --sort-by='.lastTimestamp' | tail -20
```

### Log Locations in CI/CD
1. **GitHub Actions**: Repository → Actions → Workflow run
2. **Migration logs**: Look for steps with 🚀, 🔍, and 📊 emojis
3. **Troubleshooting**: Look for 🛠️ steps when issues occur

---

## 🎉 Summary

With these enhanced tools, you now have:
- ✅ Comprehensive pre-migration checks
- 🔍 Real-time migration monitoring
- 📊 Detailed post-migration verification
- 🛠️ Powerful debugging capabilities
- 📱 Manual troubleshooting scripts

Your migrations should now be much more reliable and easier to debug when issues occur! 