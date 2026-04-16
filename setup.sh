#!/bin/bash
# Automated setup script for the k8s-mario-v2 GitOps workshop

set -e

echo "🚀 Modern DevOps Workshop - Quick Start"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Region setup ─────────────────────────────────────────────────────────────
# Prefer the environment variable; fall back to prompting.
if [ -z "$AWS_REGION" ]; then
    read -p "Enter your AWS region (e.g. us-east-1): " AWS_REGION
fi
export AWS_REGION
echo -e "${GREEN}Using region: $AWS_REGION${NC}"
echo ""

# ── Prerequisite check ───────────────────────────────────────────────────────
check_prerequisites() {
    echo "📋 Checking prerequisites..."

    MISSING=()

    command -v kubectl   &>/dev/null || MISSING+=("kubectl")
    command -v helm      &>/dev/null || MISSING+=("helm")
    command -v aws       &>/dev/null || MISSING+=("aws-cli")
    command -v docker    &>/dev/null || MISSING+=("docker")
    command -v terraform &>/dev/null || MISSING+=("terraform")
    command -v gh        &>/dev/null || MISSING+=("gh (GitHub CLI)")

    if [ ${#MISSING[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing prerequisites: ${MISSING[*]}${NC}"
        echo "Run ./script.sh to install all required tools, then try again."
        exit 1
    fi

    # Verify gh is authenticated
    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}⚠️  gh CLI is not authenticated. Run: gh auth login${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ All prerequisites installed and authenticated${NC}"
}

# ── EKS cluster ──────────────────────────────────────────────────────────────
setup_eks() {
    echo ""
    echo "🏗️  Setting up EKS cluster..."

    cd EKS-TF

    if [ ! -d ".terraform" ]; then
        echo "Initializing Terraform..."
        terraform init
    fi

    echo "Planning infrastructure..."
    terraform plan

    read -p "Apply Terraform changes? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply -auto-approve
        echo -e "${GREEN}✅ EKS cluster created${NC}"
    else
        echo "Skipping Terraform apply"
    fi

    cd ..

    echo "Updating kubeconfig..."
    aws eks update-kubeconfig --region "$AWS_REGION" --name EKS_CLOUD
    echo -e "${GREEN}✅ Kubeconfig updated${NC}"
}

# ── Argo CD ───────────────────────────────────────────────────────────────────
install_argocd() {
    echo ""
    echo "🔄 Installing Argo CD..."

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "Waiting for Argo CD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d)

    echo -e "${GREEN}✅ Argo CD installed${NC}"
    echo -e "${YELLOW}📝 Argo CD Admin Password: ${ARGOCD_PASSWORD}${NC}"
    echo ""
    echo "To access the UI:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  https://localhost:8080  |  user: admin  |  pass: ${ARGOCD_PASSWORD}"
}

# ── OPA Gatekeeper ────────────────────────────────────────────────────────────
install_gatekeeper() {
    echo ""
    echo "🔒 Installing OPA Gatekeeper..."

    kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml

    echo "Waiting for Gatekeeper to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/gatekeeper-audit -n gatekeeper-system
    kubectl wait --for=condition=available --timeout=300s \
        deployment/gatekeeper-controller-manager -n gatekeeper-system

    echo "Applying constraint templates..."
    kubectl apply -f policies/k8s-require-resources.yaml
    kubectl apply -f policies/k8s-block-latest-tag.yaml
    kubectl apply -f policies/k8s-require-non-root.yaml

    sleep 5

    echo "Applying constraints..."
    kubectl apply -f policies/production-constraints.yaml

    echo -e "${GREEN}✅ OPA Gatekeeper installed and policies applied${NC}"
}

# ── Istio ─────────────────────────────────────────────────────────────────────
install_istio() {
    echo ""
    echo "🌐 Installing Istio..."

    if ! command -v istioctl &>/dev/null; then
        echo "Downloading istioctl..."
        curl -L https://istio.io/downloadIstio | sh -
        # Add the versioned bin dir to PATH for this session
        ISTIO_DIR=$(ls -d istio-* 2>/dev/null | head -1)
        export PATH="$PATH:$PWD/$ISTIO_DIR/bin"
    fi

    istioctl install --set profile=default -y

    kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace production istio-injection=enabled --overwrite

    echo -e "${GREEN}✅ Istio installed, production namespace injection enabled${NC}"
}

# ── Flagger ───────────────────────────────────────────────────────────────────
install_flagger() {
    echo ""
    echo "🎨 Installing Flagger..."

    helm repo add flagger https://flagger.app
    helm repo update

    # Let Helm own the CRDs — do NOT pre-apply them manually.
    # The metricsServer must use the full cluster-local FQDN to reach Prometheus
    # across namespaces; short names silently fail and stall canary analysis.
    helm upgrade -i flagger flagger/flagger \
        --namespace=istio-system \
        --set meshProvider=istio \
        --set metricsServer=http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090

    echo "Installing Flagger load tester (required for canary webhooks)..."
    kubectl apply -k https://github.com/fluxcd/flagger//kustomize/tester?ref=main -n production

    echo -e "${GREEN}✅ Flagger installed${NC}"
}

# ── Prometheus + Grafana ──────────────────────────────────────────────────────
install_monitoring() {
    echo ""
    echo "📊 Installing Prometheus & Grafana..."

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    # The *SelectorNilUsesHelmValues=false flags are required so that Prometheus
    # picks up ServiceMonitors and PodMonitors installed by Istio (and others)
    # that don't carry the Helm release label.
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false

    echo "Waiting for Grafana to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/prometheus-grafana -n monitoring

    # Install Istio PodMonitors so Prometheus scrapes Istio sidecar metrics.
    # This is required for Flagger canary analysis (request-success-rate, latency).
    echo "Installing Istio PodMonitors for Prometheus..."
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/extras/prometheus-operator.yaml

    GRAFANA_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana \
        -o jsonpath="{.data.admin-password}" | base64 -d)

    echo -e "${GREEN}✅ Monitoring stack installed${NC}"
    echo -e "${YELLOW}📝 Grafana Admin Password: ${GRAFANA_PASSWORD}${NC}"
    echo ""
    echo "To access Grafana:"
    echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "  http://localhost:3000  |  user: admin  |  pass: ${GRAFANA_PASSWORD}"
}

# ── ECR repository ────────────────────────────────────────────────────────────
create_ecr() {
    echo ""
    echo "🐳 Creating ECR repository..."

    aws ecr create-repository \
        --repository-name mario \
        --region "$AWS_REGION" \
        --image-scanning-configuration scanOnPush=true 2>/dev/null \
        || echo "Repository already exists"

    ECR_URI=$(aws ecr describe-repositories \
        --repository-names mario \
        --region "$AWS_REGION" \
        --query 'repositories[0].repositoryUri' \
        --output text)

    echo -e "${GREEN}✅ ECR repository: ${ECR_URI}${NC}"

    echo "Updating kustomization with ECR URI..."
    sed -i.bak "s|<AWS_ACCOUNT_ID>.dkr.ecr.<YOUR-REGION>.amazonaws.com/mario|${ECR_URI}|g" \
        gitops/base/kustomization.yaml
    rm -f gitops/base/kustomization.yaml.bak
}

# ── Deploy app via Argo CD ────────────────────────────────────────────────────
deploy_app() {
    echo ""
    echo "🚀 Deploying application via Argo CD..."

    # Resolve GitHub username from gh CLI — no manual input needed
    GITHUB_USER=$(gh api user --jq '.login')
    echo "GitHub user: $GITHUB_USER"

    sed -i.bak "s|<YOUR-USERNAME>|${GITHUB_USER}|g" gitops/argo-apps/mario-production.yaml
    sed -i.bak "s|<YOUR-USERNAME>|${GITHUB_USER}|g" gitops/argo-apps/mario-dev.yaml
    rm -f gitops/argo-apps/*.bak

    kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f gitops/argo-apps/mario-production.yaml
    kubectl apply -f gitops/argo-apps/mario-dev.yaml

    echo -e "${GREEN}✅ Argo CD Applications submitted${NC}"
    echo ""
    echo "Monitor with:"
    echo "  kubectl get application -n argocd"
    echo "  kubectl get pods -n production -w"
}

# ── Summary ───────────────────────────────────────────────────────────────────
show_summary() {
    echo ""
    echo "=========================================="
    echo "🎉 Setup Complete!"
    echo "=========================================="
    echo ""
    echo "1. Argo CD UI:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "   https://localhost:8080"
    echo ""
    echo "2. Grafana:"
    echo "   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "   http://localhost:3000"
    echo ""
    echo "3. Deploy a new version:"
    echo "   - Edit gitops/overlays/production/kustomization.yaml (update newTag)"
    echo "   - git add/commit/push → gh pr create → gh pr merge"
    echo "   - Argo CD auto-syncs within ~3 minutes"
    echo ""
    echo "📚 Full guide: MODERN-DEVOPS-WORKSHOP.md"
    echo "🔍 Validate setup: ./validate.sh"
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main() {
    check_prerequisites

    echo ""
    echo "Select installation option:"
    echo "1) Full installation (recommended for first-time)"
    echo "2) EKS cluster only"
    echo "3) GitOps tools (Argo CD)"
    echo "4) Security tools (OPA Gatekeeper)"
    echo "5) Progressive delivery (Istio + Flagger)"
    echo "6) Monitoring (Prometheus + Grafana)"
    echo "7) Create ECR repository"
    echo "8) Deploy application"
    echo "9) Exit"
    echo ""
    read -p "Enter choice [1-9]: " choice

    case $choice in
        1)
            setup_eks
            install_argocd
            install_gatekeeper
            install_istio
            install_flagger
            install_monitoring
            create_ecr
            deploy_app
            show_summary
            ;;
        2) setup_eks ;;
        3) install_argocd ;;
        4) install_gatekeeper ;;
        5) install_istio; install_flagger ;;
        6) install_monitoring ;;
        7) create_ecr ;;
        8) deploy_app ;;
        9) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option"; exit 1 ;;
    esac
}

main
