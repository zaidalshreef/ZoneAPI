# 🐳 Docker Image Pull Troubleshooting Guide

This guide helps diagnose and resolve Docker image pull issues that can cause migration and deployment timeouts.

## Common Symptoms

- Migration pods stuck in "ContainerCreating" status for several minutes
- Migration timeouts after 60-180 seconds
- "ImagePullBackOff" or "ErrImagePull" pod statuses
- Slow deployment times on first deployment to new nodes

## Root Causes

### 1. Large Docker Images
**.NET Core applications** can produce large container images (300MB-1GB+) that take significant time to pull:
- **Runtime images**: 200-400MB base size
- **Application code**: Additional 50-200MB
- **Dependencies**: NuGet packages, static files
- **Total size**: Often 400-800MB for production applications

### 2. Network Performance
- **ACR to AKS bandwidth**: Variable based on Azure region and SKU
- **Node bandwidth**: Shared across all container pulls on the node
- **Concurrent pulls**: Multiple pods pulling simultaneously

### 3. Image Caching
- **First pull**: Full download required
- **Subsequent pulls**: Uses cached layers
- **Node restarts**: Cache cleared, full pull required again

## Diagnostic Tools

### Quick Image Size Check
```bash
# Check image size and ACR connectivity
./scripts/check-image-size.sh
```

### Manual ACR Investigation
```bash
# Login to ACR
az acr login --name <acr-name>

# Check image size
az acr repository show-manifests --name <acr-name> --repository zoneapi

# List available tags
az acr repository show-tags --name <acr-name> --repository zoneapi
```

### Kubernetes Image Pull Status
```bash
# Check pod status and events
kubectl describe pod <pod-name> -n zoneapi

# Monitor image pull events
kubectl get events -n zoneapi --field-selector reason=Pulling,reason=Pulled

# Check node image cache
kubectl describe nodes | grep -A 10 "Images:"
```

## Solutions

### 1. Increase Timeouts (Immediate Fix)

The migration timeout has been increased from 60 to 180 seconds (3 minutes):

**Migration Script:**
```bash
# Updated in scripts/run-migration.sh
TIMEOUT="${TIMEOUT:-180}"  # 3 minutes for image pull + migration
```

**CI/CD Pipeline:**
```bash
# Updated in .github/workflows/ci-cd.yml
export TIMEOUT="180"  # 3 minute timeout
```

**For Very Large Images (>500MB):**
```bash
# Set custom timeout
export TIMEOUT=300  # 5 minutes
./scripts/run-migration.sh
```

### 2. Docker Image Optimization

#### Multi-Stage Build Optimization
```dockerfile
# Optimized Dockerfile example
FROM mcr.microsoft.com/dotnet/sdk:7.0-alpine AS build
WORKDIR /src
COPY *.csproj ./
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /app

# Runtime stage - much smaller
FROM mcr.microsoft.com/dotnet/aspnet:7.0-alpine AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "ZoneAPI.dll"]
```

#### Size Reduction Techniques
```dockerfile
# Use Alpine base images (smaller)
FROM mcr.microsoft.com/dotnet/aspnet:7.0-alpine

# Remove unnecessary packages
RUN apk del --no-cache ca-certificates-bundle

# Minimize layers
RUN apt-get update && apt-get install -y package1 package2 && \
    rm -rf /var/lib/apt/lists/*

# Use .dockerignore
# Add to .dockerignore:
# **/bin/
# **/obj/
# **/node_modules/
```

### 3. Image Caching Strategies

#### Pre-pull Images to Nodes
```bash
# Create DaemonSet to pre-pull images
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: image-prepull
  namespace: zoneapi
spec:
  selector:
    matchLabels:
      name: image-prepull
  template:
    metadata:
      labels:
        name: image-prepull
    spec:
      containers:
      - name: prepull
        image: ${ACR_LOGIN_SERVER}/zoneapi:latest
        command: ["sleep", "10"]
      restartPolicy: Never
EOF
```

#### Image Pull Policy Configuration
```yaml
# In Helm charts/zoneapi/templates/deployment.yaml
spec:
  containers:
  - name: zoneapi
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    imagePullPolicy: IfNotPresent  # Use cached if available
```

### 4. ACR Performance Optimization

#### Use Premium ACR SKU
```bash
# Upgrade ACR for better performance
az acr update --name <acr-name> --sku Premium
```

#### Regional Proximity
- Deploy ACR in same region as AKS cluster
- Use Azure Private Link for ACR access

#### Geo-Replication
```bash
# Replicate ACR to multiple regions
az acr replication create --registry <acr-name> --location eastus2
```

## Monitoring and Alerting

### Real-time Monitoring
```bash
# Monitor image pull progress
kubectl get events -n zoneapi -w | grep -E "(Pulling|Pulled)"

# Watch pod creation
kubectl get pods -n zoneapi -w

# Check resource usage during pulls
kubectl top nodes
```

### Historical Analysis
```bash
# Check past image pull times
kubectl get events -n zoneapi --sort-by='.lastTimestamp' | grep Pull

# Review pod startup times
kubectl describe pod <pod-name> -n zoneapi | grep -A 5 "Events:"
```

## Timeout Configuration Reference

### Current Timeouts

| Component | Timeout | Purpose |
|-----------|---------|---------|
| Migration Script | 180s | Image pull + migration execution |
| Kubernetes Job | 600s | Overall job timeout (activeDeadlineSeconds) |
| Pod Image Pull | No limit | Inherits from kubelet settings |
| Helm Install | 300s | Chart installation timeout |

### Recommended Timeouts by Image Size

| Image Size | Pull Time | Recommended Timeout |
|------------|-----------|-------------------|
| < 200MB | 30-60s | 120s |
| 200-500MB | 60-120s | 180s |
| 500MB-1GB | 120-300s | 300s |
| > 1GB | 300s+ | 600s |

### Custom Timeout Configuration
```bash
# For large images
export TIMEOUT=300
./scripts/run-migration.sh

# For slow networks
export TIMEOUT=600
./scripts/run-migration.sh
```

## Best Practices

### Development
1. **Optimize images during development** - don't wait for production
2. **Test image pull times** locally and in staging
3. **Monitor image sizes** in CI/CD pipelines
4. **Use layer caching** in build processes

### Operations  
1. **Pre-pull images** during maintenance windows
2. **Monitor pull times** and set up alerts
3. **Use appropriate timeouts** based on image size
4. **Cache images on nodes** when possible

### CI/CD Integration
1. **Build optimized images** with multi-stage builds
2. **Scan for large layers** in security scanning
3. **Set appropriate timeouts** per environment
4. **Monitor deployment times** and image pull metrics

## Troubleshooting Commands

```bash
# Quick diagnostics
./scripts/check-image-size.sh

# Check current migration status
./scripts/debug-migration-status.sh

# Test image accessibility
az acr repository show --name <acr-name> --repository zoneapi

# Verify AKS connectivity to ACR
kubectl run test-pull --image=${ACR_LOGIN_SERVER}/zoneapi:latest --restart=Never

# Clean up test resources
kubectl delete pod test-pull
```

## Emergency Procedures

### Stuck Image Pulls
```bash
# Delete stuck pods
kubectl delete pod <stuck-pod-name> -n zoneapi --force --grace-period=0

# Clean up failed jobs
kubectl delete job <job-name> -n zoneapi

# Restart migration with higher timeout
export TIMEOUT=600
./scripts/run-migration.sh
```

### Cache Clearing
```bash
# Clear node image cache (if needed)
kubectl delete pod <pod-name> -n zoneapi
kubectl patch deployment zoneapi -n zoneapi -p '{"spec":{"template":{"metadata":{"annotations":{"date":"'$(date +'%s)'"}}}}}'
```

This troubleshooting guide helps ensure reliable deployments regardless of image size or network conditions. 