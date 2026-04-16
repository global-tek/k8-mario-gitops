# Modern DevOps Workshop - README

## 🎯 Overview

This repository demonstrates the transformation from a **classic Jenkins pipeline** to a **modern GitOps DevSecOps pipeline** for deploying a containerized application on AWS EKS.

## 📁 Repository Structure

```
k8s-mario-v2/
├── README.md                          # This file
├── MODERN-DEVOPS-WORKSHOP.md          # Complete 7-module workshop guide
├── QUICK-REFERENCE.md                 # Command cheat-sheet
├── custom_dashboard.json              # Pre-built Grafana dashboard
├── script.sh                          # Tool installer (run first)
├── setup.sh                           # Automated interactive setup
├── validate.sh                        # Post-setup validation
│
├── .github/workflows/                 # CI/CD Pipelines
│   ├── ci-pipeline.yaml              # Build, scan, push, update GitOps
│   └── security-scan.yaml            # Standalone security scanning
│
├── gitops/                            # GitOps manifests (Kustomize)
│   ├── base/                         # Shared base configs
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── overlays/                     # Environment-specific overrides
│   │   ├── dev/
│   │   │   └── kustomization.yaml
│   │   └── production/
│   │       ├── kustomization.yaml
│   │       ├── deployment-patch.yaml
│   │       └── canary.yaml
│   └── argo-apps/                    # Argo CD Application CRs
│       ├── mario-production.yaml
│       └── mario-dev.yaml
│
├── policies/                          # OPA Gatekeeper policies
│   ├── k8s-require-resources.yaml
│   ├── k8s-block-latest-tag.yaml
│   ├── k8s-require-non-root.yaml
│   └── production-constraints.yaml
│
└── EKS-TF/                            # Terraform — EKS cluster
    ├── main.tf
    ├── provider.tf
    └── backend.tf
```

## 🚀 Quick Start

### Prerequisites

- AWS Account with appropriate permissions
- Tools installed:
  - kubectl
  - helm
  - aws-cli
  - docker
  - terraform
  - git

### Option 1: Automated Setup

```bash
# Clone and enter the repository
git clone https://github.com/<your-username>/k8s-mario-v2.git
cd k8s-mario-v2

# Install all required tools (terraform, kubectl, aws-cli, docker, helm, gh)
chmod +x script.sh && ./script.sh

# Authenticate GitHub CLI, then run the interactive setup
gh auth login
chmod +x setup.sh validate.sh
./setup.sh

# Validate the installation
./validate.sh
```

### Option 2: Manual Setup

Follow the detailed step-by-step instructions in [MODERN-DEVOPS-WORKSHOP.md](MODERN-DEVOPS-WORKSHOP.md)

## 📖 Workshop Modules

The workshop is divided into 7 comprehensive modules:

1. **Repository Restructuring** - GitOps-ready structure with Kustomize
2. **GitOps with Argo CD** - Declarative, Git-driven deployments
3. **Security & Policy-as-Code** - OPA Gatekeeper for admission control
4. **Progressive Delivery** - Canary deployments with Flagger
5. **Observability** - Prometheus & Grafana monitoring
6. **CI/CD Modernization** - GitHub Actions with security scanning
7. **Testing & Validation** - End-to-end testing scenarios

## 🏗️ Architecture

### Before (Classic Pipeline)
```
Developer → Jenkins → kubectl apply → EKS
```

**Problems:**
- Manual deployments
- No drift detection
- No security scanning
- All-or-nothing releases
- Config drift possible

### After (Modern GitOps)
```
Developer → Git Push → GitHub Actions (CI)
                     ↓
              Build & Scan Image
                     ↓
              Push to ECR (Immutable)
                     ↓
              Update GitOps Repo
                     ↓
              Argo CD Sync → OPA Policy Gates
                     ↓
              Canary Deployment (Flagger)
                     ↓
              Auto Promote/Rollback (Metrics-based)
```

**Benefits:**
✅ Git as single source of truth  
✅ Automatic drift correction  
✅ Shift-left security  
✅ Progressive delivery  
✅ Immutable deployments  
✅ Instant rollbacks via `git revert`

## 🔧 Technology Stack

| Component | Tool | Purpose |
|-----------|------|---------|
| **GitOps** | Argo CD | Continuous deployment from Git |
| **CI/CD** | GitHub Actions | Build, test, security scan |
| **Policy** | OPA Gatekeeper | Admission control & compliance |
| **Progressive Delivery** | Flagger | Canary & blue-green deployments |
| **Service Mesh** | Istio | Traffic management |
| **Monitoring** | Prometheus & Grafana | Metrics & visualization |
| **Image Registry** | AWS ECR | Container image storage |
| **Infrastructure** | Terraform | EKS cluster provisioning |
| **Security Scanning** | Trivy | Vulnerability detection |

## 📋 Common Operations

### Deploy a New Version

```bash
# 1. Create a feature branch and update the image tag
git checkout -b feature/v1.2.0
# Edit gitops/overlays/production/kustomization.yaml → update newTag

# 2. Commit, push, open a PR, and merge via gh CLI
git add gitops/overlays/production/kustomization.yaml
git commit -m "deploy: v1.2.0"
git push origin feature/v1.2.0
gh pr create --title "deploy: v1.2.0" --base main
gh pr merge --merge --delete-branch

# 3. Watch Argo CD auto-sync (within ~3 minutes)
kubectl get application -n argocd mario-production -w
```

### Rollback

```bash
# Simple git revert
git revert HEAD
git push

# Argo CD auto-syncs to previous state
```

### Access UIs

```bash
# Argo CD
kubectl port-forward svc/argocd-server -n argocd 8080:443
# → https://localhost:8080

# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# → http://localhost:3000
```

## 🔍 Validation

Run the validation script to check your setup:

```bash
./validate.sh
```

Expected output:
```
✅ EKS cluster is accessible
✅ Argo CD server is running
✅ Constraint templates are installed
✅ Istio is installed
✅ Flagger is installed
✅ Prometheus operator is installed
✅ Production application is synced

🎉 All critical checks passed!
```

## 📚 Documentation

- **[MODERN-DEVOPS-WORKSHOP.md](MODERN-DEVOPS-WORKSHOP.md)** - Complete 7-module workshop guide
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Command reference cheat-sheet
- **[custom_dashboard.json](custom_dashboard.json)** - Pre-built Grafana dashboard (import via Grafana UI)

## 🎓 Learning Objectives

After completing this workshop, you will:

- ✅ Understand GitOps principles and practices
- ✅ Deploy applications declaratively with Argo CD
- ✅ Implement shift-left security with scanning and policies
- ✅ Perform canary deployments with automatic rollback
- ✅ Monitor applications with Prometheus and Grafana
- ✅ Build modern CI/CD pipelines with GitHub Actions
- ✅ Enforce compliance with policy-as-code

## 🐛 Troubleshooting

Common issues and solutions:

### Argo CD Not Syncing
```bash
argocd app get mario-production --refresh --hard
argocd app sync mario-production --force
```

### Pod Image Pull Errors
```bash
# Create ECR credentials (set AWS_REGION first)
kubectl create secret docker-registry ecr-secret \
  --docker-server=<ecr-uri> \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region $AWS_REGION) \
  --namespace=production
```

### Canary Deployment Stuck
```bash
# Check Flagger logs
kubectl logs -n istio-system deployment/flagger -f

# Reset canary
kubectl delete canary -n production mario-canary
kubectl apply -f gitops/overlays/production/canary.yaml
```

For more troubleshooting, see the [Workshop Guide](MODERN-DEVOPS-WORKSHOP.md#troubleshooting-guide).

## 🤝 Contributing

This is a learning project. Feel free to:
- Open issues for questions
- Submit PRs for improvements
- Share your experience

## 📄 License

MIT License - feel free to use this for learning and training purposes.

## 🙏 Acknowledgments

Based on modern DevOps best practices from:
- CNCF GitOps Working Group
- Argo CD community
- Flagger project
- Open Policy Agent community

---

**Ready to get started?** 

👉 Jump to [MODERN-DEVOPS-WORKSHOP.md](MODERN-DEVOPS-WORKSHOP.md) for the complete guide!

**Questions?**  
Check the [Quick Reference Guide](QUICK-REFERENCE.md) for common commands and operations.
