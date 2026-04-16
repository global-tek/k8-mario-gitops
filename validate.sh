#!/bin/bash
# Validation Script for Modern DevOps Setup

set -e

# Use AWS_REGION env var if set; otherwise prompt
if [ -z "$AWS_REGION" ]; then
    read -p "Enter your AWS region (e.g. us-east-1): " AWS_REGION
fi
export AWS_REGION

echo "🔍 Validating Modern DevOps Setup"
echo "=================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

check_pass() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}❌ $1${NC}"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check EKS cluster
echo "1. Checking EKS cluster..."
if kubectl cluster-info &> /dev/null; then
    check_pass "EKS cluster is accessible"
else
    check_fail "Cannot access EKS cluster"
fi

# Check Argo CD
echo ""
echo "2. Checking Argo CD..."
if kubectl get namespace argocd &> /dev/null; then
    check_pass "Argo CD namespace exists"
    
    if kubectl get deployment -n argocd argocd-server &> /dev/null; then
        if kubectl get deployment -n argocd argocd-server -o jsonpath='{.status.availableReplicas}' | grep -q "1"; then
            check_pass "Argo CD server is running"
        else
            check_fail "Argo CD server is not ready"
        fi
    else
        check_fail "Argo CD server deployment not found"
    fi
else
    check_fail "Argo CD namespace not found"
fi

# Check OPA Gatekeeper
echo ""
echo "3. Checking OPA Gatekeeper..."
if kubectl get namespace gatekeeper-system &> /dev/null; then
    check_pass "Gatekeeper namespace exists"
    
    if kubectl get constrainttemplates &> /dev/null; then
        TEMPLATES=$(kubectl get constrainttemplates --no-headers | wc -l)
        if [ "$TEMPLATES" -ge 3 ]; then
            check_pass "Constraint templates are installed ($TEMPLATES found)"
        else
            check_warn "Only $TEMPLATES constraint templates found (expected 3+)"
        fi
    fi
    
    if kubectl get constraints &> /dev/null; then
        CONSTRAINTS=$(kubectl get constraints --no-headers | wc -l)
        if [ "$CONSTRAINTS" -ge 3 ]; then
            check_pass "Constraints are applied ($CONSTRAINTS found)"
        else
            check_warn "Only $CONSTRAINTS constraints found (expected 3+)"
        fi
    fi
else
    check_fail "Gatekeeper namespace not found"
fi

# Check Istio
echo ""
echo "4. Checking Istio..."
if kubectl get namespace istio-system &> /dev/null; then
    check_pass "Istio namespace exists"
    
    if kubectl get deployment -n istio-system istiod &> /dev/null; then
        check_pass "Istiod is installed"
    else
        check_fail "Istiod not found"
    fi
    
    # Check if production namespace has istio injection
    if kubectl get namespace production -o jsonpath='{.metadata.labels.istio-injection}' | grep -q "enabled"; then
        check_pass "Production namespace has Istio injection enabled"
    else
        check_warn "Production namespace does not have Istio injection enabled"
    fi
else
    check_fail "Istio namespace not found"
fi

# Check Flagger
echo ""
echo "5. Checking Flagger..."
if kubectl get deployment -n istio-system flagger &> /dev/null; then
    check_pass "Flagger is installed"
else
    check_fail "Flagger not found"
fi

# Check Monitoring
echo ""
echo "6. Checking Monitoring Stack..."
if kubectl get namespace monitoring &> /dev/null; then
    check_pass "Monitoring namespace exists"
    
    if kubectl get deployment -n monitoring prometheus-kube-prometheus-operator &> /dev/null; then
        check_pass "Prometheus operator is installed"
    else
        check_warn "Prometheus operator not found"
    fi
    
    if kubectl get deployment -n monitoring prometheus-grafana &> /dev/null; then
        check_pass "Grafana is installed"
    else
        check_warn "Grafana not found"
    fi
else
    check_fail "Monitoring namespace not found"
fi

# Check namespaces
echo ""
echo "7. Checking Application Namespaces..."
if kubectl get namespace production &> /dev/null; then
    check_pass "Production namespace exists"
else
    check_warn "Production namespace not found"
fi

if kubectl get namespace dev &> /dev/null; then
    check_pass "Dev namespace exists"
else
    check_warn "Dev namespace not found"
fi

# Check Argo CD applications
echo ""
echo "8. Checking Argo CD Applications..."
if kubectl get application -n argocd mario-production &> /dev/null; then
    check_pass "Production application configured"
    
    SYNC_STATUS=$(kubectl get application -n argocd mario-production -o jsonpath='{.status.sync.status}')
    if [ "$SYNC_STATUS" = "Synced" ]; then
        check_pass "Production application is synced"
    else
        check_warn "Production application sync status: $SYNC_STATUS"
    fi
else
    check_warn "Production application not found"
fi

# Check ECR repository
echo ""
echo "9. Checking ECR Repository..."
if aws ecr describe-repositories --repository-names mario --region $AWS_REGION &> /dev/null; then
    check_pass "ECR repository exists"
    
    ECR_URI=$(aws ecr describe-repositories --repository-names mario --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
    echo "   Repository URI: $ECR_URI"
else
    check_fail "ECR repository not found"
fi

# Check GitOps structure
echo ""
echo "10. Checking GitOps Repository Structure..."
if [ -d "gitops/base" ]; then
    check_pass "GitOps base directory exists"
else
    check_fail "GitOps base directory not found"
fi

if [ -d "gitops/overlays/production" ]; then
    check_pass "Production overlay exists"
else
    check_fail "Production overlay not found"
fi

if [ -d "policies" ]; then
    check_pass "Policies directory exists"
else
    check_fail "Policies directory not found"
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All critical checks passed!${NC}"
    echo "Your modern DevOps setup is ready to use."
    exit 0
else
    echo -e "${YELLOW}⚠️  Some checks failed.${NC}"
    echo "Please review the failed checks and fix them."
    echo "Refer to MODERN-DEVOPS-WORKSHOP.md for troubleshooting."
    exit 1
fi
