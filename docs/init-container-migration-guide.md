# 🚀 Init Container Migration Guide

This guide explains the **init container approach** for database migrations in ZoneAPI, which is a cleaner and more Kubernetes-native solution compared to separate migration jobs.

## 🎯 Architecture Overview

### **Before: Separate Migration Jobs** ❌
```
Build → Infrastructure → Docker Build → Migration Job → Deploy Application
                                            ↓
                                       Separate Job
                                       Secret Conflicts
                                       Complex Dependencies
```

### **Now: Init Container Approach** ✅
```
Build → Infrastructure → Docker Build → Deploy Application
                                            ↓
                                       Init Container (Migration)
                                       Main Container (Application)
                                       Single Helm Release
```

## 🏗️ How It Works

### **Deployment Flow**
1. **Helm Deploy Starts** - Single `helm upgrade --install` command
2. **Secret Created** - Helm creates `zoneapi-db-secret` with proper metadata
3. **Pod Scheduled** - Kubernetes schedules the application pod
4. **Init Container Runs** - Migration executes using `./efbundle`
5. **Init Container Completes** - Database is migrated successfully
6. **Main Container Starts** - Application starts with updated database
7. **Deployment Complete** - Single atomic operation

### **Init Container Configuration**
```yaml
initContainers:
  - name: migration
    image: "acrzoneapidevx0lo50gh.azurecr.io/zoneapi:latest"
    command: ["./efbundle"]
    args:
      - "--connection"
      - "Host=psql-server;Port=5432;Database=zone;Username=postgres;Password=$(DB_PASSWORD);CommandTimeout=300;Timeout=60;"
      - "--verbose"
    env:
      - name: DB_PASSWORD
        valueFrom:
          secretKeyRef:
            name: zoneapi-db-secret
            key: password
```

## ✅ Advantages

### **1. Simplified Architecture**
- **Single Helm Release** - Everything managed together
- **No Secret Conflicts** - Helm creates all resources with proper metadata
- **Atomic Deployment** - Migration and application deploy as one unit
- **Fewer CI/CD Stages** - Reduced from 6 stages to 4 stages

### **2. Better Resource Management** 
- **Shared Configuration** - Same image, secrets, and environment variables
- **Automatic Ordering** - Init container always runs before main container
- **Resource Efficiency** - No separate migration pods running continuously
- **Proper Cleanup** - Init containers are automatically cleaned up

### **3. Kubernetes Best Practices**
- **Native Pattern** - Init containers are designed for this use case
- **Helm Compliance** - Follows Helm resource management standards
- **Pod Lifecycle** - Integrated into standard Kubernetes pod lifecycle
- **Health Checks** - Pod health depends on both init and main containers

### **4. Operational Benefits**
- **Simplified Debugging** - All components in single pod
- **Consistent Logging** - Centralized log collection
- **Rollback Safety** - Failed migrations prevent app start
- **Version Consistency** - Migration and app always use same image version

## 🔧 Implementation Details

### **Helm Chart Changes**

#### **Added Init Container** (in `deployment.yaml`)
```yaml
initContainers:
  - name: migration
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    command: ["./efbundle"]
    args: [...]
    env: [...]
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m" 
        memory: "512Mi"
```

#### **Secret Template** (in `secret.yaml`)
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: zoneapi-db-secret
  labels:
    {{- include "zoneapi.labels" . | nindent 4 }}
type: Opaque
data:
  password: {{ .Values.database.password | b64enc }}
```

### **CI/CD Pipeline Changes**

#### **Removed Stages**
- ❌ `run-migration` job (entire 678-line job removed)
- ❌ Secret ownership fix step (51-line step removed)
- ❌ Complex dependency management

#### **Updated Dependencies**
```yaml
# Before
needs: [deploy-infrastructure, docker-build-push, run-migration]

# After  
needs: [deploy-infrastructure, docker-build-push]
```

#### **Simplified Deployment**
```yaml
- name: 🚀 Deploy Application (with Init Container Migration)
  run: |
    helm upgrade --install zoneapi ./charts/zoneapi \
      --namespace zoneapi \
      --create-namespace \
      --set database.password="${{ secrets.POSTGRES_ADMIN_PASSWORD }}" \
      --wait --timeout=5m
```

## 📊 Performance Comparison

| Aspect | Separate Jobs | Init Container |
|--------|---------------|----------------|
| **Pipeline Stages** | 6 stages | 4 stages |
| **Total Time** | ~8-12 minutes | ~6-8 minutes |
| **Secret Management** | Complex (ownership fixes) | Simple (Helm managed) |
| **Resource Usage** | 2 separate pods | 1 pod (2 containers) |
| **Failure Recovery** | Manual intervention often needed | Automatic retry with pod restart |
| **Debugging** | Multiple places to check | Single pod to examine |

## 🛠️ Troubleshooting

### **Common Issues**

#### **Init Container Fails**
```bash
# Check init container logs
kubectl logs <pod-name> -c migration -n zoneapi

# Check init container status
kubectl describe pod <pod-name> -n zoneapi
```

#### **Application Won't Start**
- **Root Cause**: Init container must complete successfully first
- **Solution**: Fix migration issues, pod will restart automatically
- **Check**: `kubectl get pods -n zoneapi -w`

#### **Database Connection Issues**
```bash
# Test database connectivity
kubectl run db-test --image=postgres:15-alpine --rm -it --restart=Never \
  --namespace=zoneapi \
  --env="PGPASSWORD=$(kubectl get secret zoneapi-db-secret -n zoneapi -o jsonpath='{.data.password}' | base64 -d)" \
  -- psql -h <db-host> -U postgres -d zone
```

### **Debugging Commands**

```bash
# Monitor deployment progress
kubectl get pods -n zoneapi -w

# Check init container logs
kubectl logs deployment/zoneapi -c migration -n zoneapi

# Check main application logs  
kubectl logs deployment/zoneapi -c zoneapi -n zoneapi

# Get detailed pod information
kubectl describe pod <pod-name> -n zoneapi

# Check Helm release status
helm status zoneapi -n zoneapi
```

## 🔄 Migration Path

### **For Existing Deployments**

1. **Clean Up Old Resources**
   ```bash
   # Remove old migration jobs
   kubectl delete jobs -l app.kubernetes.io/component=migration -n zoneapi
   
   # Clean up old secrets (if needed)
   ./scripts/fix-secret-ownership.sh
   ```

2. **Deploy New Version**
   ```bash
   # Deploy with init container approach
   helm upgrade --install zoneapi ./charts/zoneapi \
     --namespace zoneapi \
     --set database.password="<password>"
   ```

3. **Verify Migration**
   ```bash
   # Check init container completed
   kubectl get pods -n zoneapi
   
   # Verify application is running
   kubectl get pods -n zoneapi -l app.kubernetes.io/name=zoneapi
   ```

### **For New Deployments**

Simply run the standard CI/CD pipeline - everything is handled automatically:

```bash
git push origin main
# Pipeline will:
# 1. Build and test application
# 2. Deploy infrastructure  
# 3. Build and push Docker image
# 4. Deploy application with init container migration
```

## 📚 Best Practices

### **Development**
- **Test migrations locally** before deploying
- **Keep migrations idempotent** - safe to run multiple times
- **Monitor init container resource usage** - adjust limits if needed
- **Use meaningful migration names** - for easier troubleshooting

### **Operations**
- **Monitor pod startup times** - init containers affect startup
- **Set appropriate timeouts** - migrations can take time
- **Plan for rollbacks** - failed migrations prevent app start
- **Regular database maintenance** - keep migrations fast

### **CI/CD**
- **Set reasonable timeouts** - `--timeout=5m` for Helm deployments
- **Use `--wait` flag** - ensure init container completes before success
- **Monitor resource usage** - adjust requests/limits as needed
- **Test in staging first** - validate migration behavior

## 🎉 Summary

The **init container approach** provides a cleaner, more maintainable, and Kubernetes-native solution for database migrations:

- ✅ **Simplified Architecture** - Single Helm release manages everything
- ✅ **No Secret Conflicts** - Proper Helm metadata from start
- ✅ **Atomic Deployments** - Migration and app as single unit
- ✅ **Better Performance** - Fewer stages, faster deployments
- ✅ **Easier Debugging** - Everything in one place
- ✅ **Best Practices** - Follows Kubernetes and Helm conventions

This approach eliminates the complexity of separate migration jobs and provides a more robust, maintainable solution for production deployments. 