# 🔒 Security Scanning Guide

This document explains the Trivy security scanning implementation in the ZoneAPI CI/CD pipeline.

## Overview

The pipeline includes comprehensive security scanning using [Trivy](https://github.com/aquasecurity/trivy), an all-in-one vulnerability scanner that detects:

- 🔍 **Vulnerabilities** in OS packages, language packages, and container images
- 🕵️ **Secrets** like API keys, passwords, and tokens
- 📋 **Misconfigurations** in Infrastructure as Code (IaC) files
- 🐳 **Container Image** vulnerabilities and best practices

## Pipeline Integration

### Stage 1: Source Code Security Scan
**Job:** `security-scan`  
**Runs:** After build-and-test, before infrastructure deployment  
**Scans:** Source code, secrets, configuration files

```yaml
- Source code vulnerability scan (SARIF + table format)
- Secret detection (fails pipeline if secrets found)
- GitHub Security tab integration
- Artifact uploads for review
```

### Stage 2: Container Image Security Scan
**Job:** `docker-build-push`  
**Runs:** After Docker image is built  
**Scans:** Built container image, filesystem

```yaml
- Container image vulnerability scan
- Filesystem security analysis
- Multi-format reporting (SARIF + table)
- Configurable severity thresholds
```

## Security Reports

### GitHub Security Tab
- **Location:** Repository → Security → Code scanning alerts
- **Format:** SARIF (Static Analysis Results Interchange Format)
- **Categories:** 
  - `trivy-source-code` - Source code vulnerabilities
  - `trivy-container-image` - Container image vulnerabilities

### Pipeline Artifacts
- **Source Security Report** (`trivy-source-security-report`)
  - Retention: 30 days
  - Contains: SARIF files for manual review
- **Image Security Reports** (`trivy-security-reports`)
  - Retention: 30 days
  - Contains: SARIF + human-readable table reports

## Configuration

### Severity Levels
- **CRITICAL** - Immediate action required, fails pipeline
- **HIGH** - Should be addressed, fails pipeline
- **MEDIUM** - Should be reviewed
- **LOW** - Informational
- **UNKNOWN** - Unclassified

### Current Pipeline Settings

#### Source Code Scan
```yaml
severity: 'CRITICAL,HIGH,MEDIUM'
ignore-unfixed: true
exit-code: '1' (for secrets only)
```

#### Container Image Scan
```yaml
severity: 'CRITICAL,HIGH'
ignore-unfixed: true
exit-code: '1'
```

## Local Testing

### Prerequisites
```bash
# Install Trivy (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy
```

### Run Local Security Tests
```bash
# Run comprehensive security tests
./scripts/test-trivy-scan.sh

# Quick source code scan
trivy fs . --severity CRITICAL,HIGH

# Secret detection
trivy fs . --scanners secret

# Dockerfile security check
trivy config Dockerfile
```

## Handling Vulnerabilities

### 1. Review Security Alerts
1. Go to Repository → Security → Code scanning alerts
2. Review each alert for severity and impact
3. Click on alerts for detailed information and remediation steps

### 2. Fix Vulnerabilities

#### For Source Code Dependencies
```bash
# .NET packages
dotnet list package --outdated
dotnet add package [PackageName] --version [NewVersion]

# Update all packages
dotnet outdated --upgrade
```

#### For Container Base Images
```dockerfile
# Update base image in Dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:7.0-alpine AS base
# ↓ Update to latest patched version
FROM mcr.microsoft.com/dotnet/aspnet:7.0.15-alpine AS base
```

### 3. Handle False Positives

Create `.trivyignore` file in repository root:
```
# Ignore specific CVE (with justification)
CVE-2023-12345 # False positive: not applicable to our use case

# Ignore by package
npm:lodash@4.17.20

# Ignore by file
Dockerfile:3
```

## Security Best Practices

### 🔒 Secrets Management
- ✅ Use GitHub Secrets for sensitive data
- ✅ Use Azure Key Vault for production secrets
- ❌ Never commit API keys, passwords, or tokens
- ❌ Avoid hardcoded connection strings

### 🐳 Container Security
- ✅ Use official, minimal base images (alpine)
- ✅ Update base images regularly
- ✅ Run containers as non-root user
- ✅ Use multi-stage builds to reduce attack surface

### 📦 Dependency Management
- ✅ Keep dependencies up to date
- ✅ Review security advisories regularly
- ✅ Use dependency scanning tools
- ✅ Remove unused dependencies

## Troubleshooting

### Common Issues

#### "Resource not accessible by integration"
**Cause:** Missing GitHub Actions permissions  
**Solution:** Verify workflow has `security-events: write` permission

#### "Failed to upload SARIF"
**Cause:** SARIF file format issues  
**Solution:** Check SARIF file validity with GitHub's SARIF validator

#### "High vulnerability count"
**Cause:** Outdated dependencies  
**Solution:** Update packages and base images

### Pipeline Failures

#### Security Scan Failures
1. Check the security scan job logs
2. Review failed security checks
3. Fix CRITICAL/HIGH vulnerabilities
4. Consider adding exceptions for false positives

#### SARIF Upload Failures
1. Verify GitHub Actions permissions
2. Check SARIF file format
3. Ensure running on supported events (push to main/master)

## Monitoring and Maintenance

### Regular Tasks
- **Weekly:** Review new security alerts
- **Monthly:** Update dependencies and base images
- **Quarterly:** Review and update security policies

### Metrics to Track
- Number of vulnerabilities by severity
- Time to remediation for CRITICAL/HIGH vulnerabilities
- Percentage of scans passing without issues
- False positive rate

## References

- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning)
- [SARIF Specification](https://sarifweb.azurewebsites.net/)
- [Container Security Best Practices](https://docs.docker.com/develop/security-best-practices/) 