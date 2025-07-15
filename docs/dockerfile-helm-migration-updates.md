# Dockerfile, Helm Charts, and CI/CD Pipeline Updates

## Overview

This document summarizes the changes made to align the Dockerfile, Helm charts, and CI/CD pipeline with the new efbundle approach for database migrations.

## Changes Made

### 1. Dockerfile Updates ✅

**File**: `Dockerfile`

**Key Changes**:
- Updated to use .NET 7.0 SDK with compatible dotnet-ef tool (7.0.20)
- Simplified single-stage build approach
- Migration bundle placed at `/app/efbundle` (matching docker-compose expectations)
- Working directory set to `/out` for application
- User setup with UID 10001 for security

**Before**: Multi-stage build with compatibility issues
**After**: Single-stage build with efbundle at correct path

### 2. Helm Values Configuration Updates ✅

**File**: `charts/zoneapi/values.yaml`

**Key Changes**:
- Updated `securityContext.runAsUser` to `10001` (matching Dockerfile)
- Updated `podSecurityContext.fsGroup` to `10001`
- Set `readOnlyRootFilesystem: false` to allow `/tmp` writes
- Added migration bundle path configuration: `/app/efbundle`
- Improved health check timings for .NET 7.0 startup characteristics

### 3. Migration Job Template Updates ✅

**File**: `charts/zoneapi/templates/migration-job.yaml`

**Key Changes**:
- Updated working directory to `/app` where efbundle is located
- Fixed command execution: `./efbundle` from `/app` directory
- Added proper security context with `fsGroup: 10001`
- Increased resource limits for migration operations
- Added proper capabilities dropping for security

**Critical Fix**: Migration now runs from correct directory with efbundle

### 4. Deployment Template Updates ✅

**File**: `charts/zoneapi/templates/deployment.yaml`

**Key Changes**:
- Added `workingDir: /out` to match Dockerfile
- Added `/tmp` volume mount for temporary files
- Updated probe paths with defaults
- Enhanced environment variable configuration

### 5. Migration Script Updates ✅

**File**: `scripts/run-migration.sh`

**Key Changes**:
- Complete rewrite for efbundle approach
- Added Helm template-based job creation
- Enhanced error handling and logging
- Added migration verification and cleanup
- Proper environment variable handling

**New Features**:
- Uses Helm templates for consistent job creation
- Better error reporting and debugging
- Automatic cleanup of old migration jobs

### 6. CI/CD Pipeline Updates ✅

**File**: `.github/workflows/ci-cd.yml`

**Key Changes**:
- Already using .NET 7.0.x (✅ No change needed)
- Added `DB_PASSWORD` environment variable for migration script
- Enhanced logging and configuration display
- Added Helm installation for migration job creation

## Migration Approach Comparison

### Previous Approach (Problematic)
```yaml
# Pre-install hooks (blocking)
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-weight: "-1"
```

### New Approach (Industry Best Practice)
```yaml
# Standalone job with efbundle
apiVersion: batch/v1
kind: Job
# No hooks - independent execution
```

## Key Benefits Achieved

### ✅ Compatibility Fixed
- .NET 7.0 + dotnet-ef 7.0.20 compatibility resolved
- No more version mismatch errors

### ✅ Security Enhanced
- Proper non-root user (UID 10001)
- Minimal capabilities
- Secure volume mounts

### ✅ Reliability Improved
- Independent migration jobs (no blocking deployments)
- Better error handling and retry logic
- Proper resource allocation

### ✅ Observability Enhanced
- Comprehensive logging
- Migration verification
- Job cleanup automation

## Testing Results

### Local Testing ✅
- Docker Compose: All services healthy
- Database: Tables created successfully
- API: All endpoints responding correctly
- Migration: efbundle executed successfully

### Expected CI/CD Improvements
- Faster migration execution
- Better error reporting
- No pre-install hook blocking
- Independent migration troubleshooting

## Migration Path

1. **Dockerfile**: Fixed .NET/dotnet-ef compatibility ✅
2. **Helm Charts**: Updated for new container structure ✅
3. **Scripts**: Rewritten for efbundle approach ✅
4. **CI/CD**: Enhanced with proper environment variables ✅

## Next Steps

1. **Test in Azure AKS**: Verify pipeline works end-to-end
2. **Monitor Performance**: Check migration timing improvements
3. **Validate Security**: Ensure non-root user works correctly
4. **Documentation**: Update README with new approach

## Rollback Plan

If issues arise, the previous configuration can be restored by:
1. Reverting Dockerfile to previous multi-stage approach
2. Restoring original Helm values
3. Re-enabling pre-install hooks (not recommended)

However, the new approach follows Microsoft and industry best practices and should be more reliable.

---

**Summary**: All components updated to work cohesively with the efbundle approach, following .NET 7.0 + AKS industry best practices. 