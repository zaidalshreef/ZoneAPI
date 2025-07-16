#!/bin/bash

# Test script for Trivy security scanning
# This validates that Trivy works correctly before running in CI/CD

set -e

echo "=== 🔒 TRIVY SECURITY SCANNING TEST ==="
echo ""

# Check if Trivy is installed
if ! command -v trivy &> /dev/null; then
    echo "❌ Trivy is not installed. Installing..."
    
    # Install Trivy (Ubuntu/Debian)
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install wget apt-transport-https gnupg lsb-release -y
        wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
        echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
        sudo apt-get update
        sudo apt-get install trivy -y
    else
        echo "❌ Please install Trivy manually: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
        exit 1
    fi
fi

echo "✅ Trivy version: $(trivy --version)"
echo ""

# Test 1: Filesystem scan for source code vulnerabilities
echo "=== 🔍 TEST 1: Source Code Vulnerability Scan ==="
trivy fs . \
    --format table \
    --severity CRITICAL,HIGH,MEDIUM \
    --ignore-unfixed \
    --no-progress

echo ""

# Test 2: Secret detection scan
echo "=== 🕵️ TEST 2: Secret Detection Scan ==="
trivy fs . \
    --scanners secret \
    --format table \
    --no-progress

echo ""

# Test 3: Dockerfile scan
echo "=== 🐳 TEST 3: Dockerfile Security Scan ==="
if [ -f "Dockerfile" ]; then
    trivy config Dockerfile \
        --format table \
        --no-progress
else
    echo "❌ Dockerfile not found"
fi

echo ""

# Test 4: Generate SARIF report (like CI/CD does)
echo "=== 📋 TEST 4: Generate SARIF Report ==="
trivy fs . \
    --format sarif \
    --output trivy-test-results.sarif \
    --no-progress

if [ -f "trivy-test-results.sarif" ]; then
    echo "✅ SARIF report generated: trivy-test-results.sarif"
    echo "📊 Report size: $(wc -c < trivy-test-results.sarif) bytes"
    
    # Clean up test file
    rm trivy-test-results.sarif
else
    echo "❌ Failed to generate SARIF report"
    exit 1
fi

echo ""
echo "🎉 All Trivy security tests completed successfully!"
echo ""
echo "💡 Tips:"
echo "   - Review any CRITICAL or HIGH vulnerabilities found"
echo "   - Update dependencies if vulnerabilities are fixable"
echo "   - Consider adding .trivyignore file for false positives"
echo "   - The CI/CD pipeline will run these same scans automatically" 