# PostgreSQL VDB Platform - Deployment Guide

This guide provides step-by-step instructions for deploying the PostgreSQL VDB platform using ArgoCD and the Delphix operator.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Install PostgresVDB Operator](#install-postgresvdb-operator)
4. [Configure Git Repository](#configure-git-repository)
5. [Deploy ArgoCD Applications](#deploy-argocd-applications)
6. [Verify Deployment](#verify-deployment)
7. [Managing Environments](#managing-environments)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

- **Kubernetes cluster** (v1.24 or higher)
  ```bash
  kubectl version --short
  ```

- **ArgoCD** (v2.8 or higher)
  ```bash
  kubectl get pods -n argocd
  ```

- **Helm** (v3.8 or higher)
  ```bash
  helm version
  ```

- **Git CLI**
  ```bash
  git --version
  ```

### Required Access

- Kubernetes cluster admin access
- Git repository with write permissions
- ArgoCD access (UI or CLI)
- Delphix Data Control Tower (DCT) access (for source databases)

### Optional Tools

- **ArgoCD CLI** (for command-line management)
  ```bash
  # Install ArgoCD CLI
  brew install argocd  # macOS
  # or download from https://argo-cd.readthedocs.io/en/stable/cli_installation/
  ```

- **kubectl plugins**
  ```bash
  kubectl krew install ctx ns  # Context and namespace switcher
  ```

## Initial Setup

### 1. Clone the Repository

```bash
# Clone your forked repository
git clone https://github.com/your-org/vdb-platform.git
cd vdb-platform

# Verify structure
tree -L 2
```

Expected structure:
```
.
├── README.md
├── DEPLOY.md
├── applications/
│   ├── app-of-apps.yaml
│   ├── applicationset-environments.yaml
│   └── applicationset-features.yaml
├── charts/
│   └── postgres-vdb/
├── crds/
│   └── postgresvdb.yaml
├── environments/
│   ├── features/
│   ├── dev.yaml
│   ├── qa.yaml
│   └── values-prod.yaml
└── scripts/
    ├── create-feature-env.sh
    └── cleanup-feature-env.sh
```

### 2. Create Kubernetes Namespace

```bash
# Create namespace for VDB resources
kubectl create namespace postgres-vdbs

# Verify namespace
kubectl get namespace postgres-vdbs
```

### 3. Configure Storage Class (if needed)

If your cluster doesn't have the `de-fs-storage` storage class, update the base values:

```bash
# List available storage classes
kubectl get storageclass

# Update the storage class in charts/postgres-vdb/values.yaml
# Replace "de-fs-storage" with your storage class name
```

## Install PostgresVDB Operator

### Option 1: Using Manifest Files

```bash
# Install the CRD
kubectl apply -f crds/postgresvdb.yaml

# Verify CRD installation
kubectl get crd postgresvdbs.core.delphix.com

# Install the operator (adjust URL to actual operator deployment)
kubectl apply -f https://raw.githubusercontent.com/delphix/postgres-vdb-operator/main/deploy/operator.yaml

# Verify operator is running
kubectl get pods -n postgres-vdb-operator
```

### Option 2: Using Helm (if available)

```bash
# Add Delphix Helm repository
helm repo add delphix https://charts.delphix.com
helm repo update

# Install the operator
helm install postgres-vdb-operator delphix/postgres-vdb-operator \
  --namespace postgres-vdb-operator \
  --create-namespace

# Verify installation
helm list -n postgres-vdb-operator
```

### Verify Operator Installation

```bash
# Check operator logs
kubectl logs -n postgres-vdb-operator -l app=postgres-vdb-operator --tail=50

# Verify CRD is available
kubectl api-resources | grep postgresvdb
```

## Configure Git Repository

### 1. Update Repository URLs

Update the repository URL in all ArgoCD application files:

```bash
# Replace placeholder URL with your actual repository
find applications -name "*.yaml" -exec sed -i '' \
  's|https://github.com/your-org/vdb-platform.git|https://github.com/ACTUAL-ORG/ACTUAL-REPO.git|g' {} \;
```

### 2. Update Source Database Configuration

Edit `charts/postgres-vdb/values.yaml` to configure your Delphix source:

```yaml
global:
  # Update with your Delphix DCT source
  sourceDatabase: "YOUR-DCT-HOST:YOUR-SOURCE-DB"
  postgresImage: "postgres:16.9"
```

### 3. Update Environment-Specific Passwords

**IMPORTANT**: Replace default passwords in environment files:

```bash
# Generate secure passwords
openssl rand -base64 16

# Update each environment file
# environments/dev.yaml
# environments/qa.yaml
# environments/values-prod.yaml (CRITICAL - use secrets in production!)
```

### 4. Commit and Push Changes

```bash
git add .
git commit -m "Configure repository for deployment"
git push origin main
```

## Deploy ArgoCD Applications

### 1. Install ArgoCD (if not already installed)

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### 2. Access ArgoCD UI

```bash
# Port forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser to https://localhost:8080
# Login: admin / (password from previous step)
```

### 3. Configure ArgoCD Git Repository (Optional - for private repos)

```bash
# Login to ArgoCD CLI
argocd login localhost:8080 --username admin --password <password> --insecure

# Add Git repository credentials
argocd repo add https://github.com/your-org/vdb-platform.git \
  --username <username> \
  --password <token>
```

### 4. Deploy the Application of Applications

```bash
# Apply the root application
kubectl apply -f applications/app-of-apps.yaml -n argocd

# Verify application is created
argocd app get postgres-vdb-platform

# Sync the application (if not auto-sync)
argocd app sync postgres-vdb-platform
```

### 5. Monitor ApplicationSets

```bash
# Check ApplicationSets
kubectl get applicationset -n argocd

# View generated applications
argocd app list

# You should see applications like:
# - postgres-vdb-dev
# - postgres-vdb-qa
# - postgres-vdb-prod (if values file exists)
# - postgres-vdb-feat-123
# - postgres-vdb-feat-456
```

## Verify Deployment

### 1. Check ArgoCD Applications

```bash
# List all applications
argocd app list

# Get detailed status of an application
argocd app get postgres-vdb-dev

# Watch sync progress
argocd app sync postgres-vdb-dev --watch
```

### 2. Verify PostgresVDB Resources

```bash
# List all VDBs across namespaces
kubectl get postgresvdb --all-namespaces

# Check specific VDB status
kubectl describe postgresvdb dev-vdb -n postgres-vdbs-dev

# Expected output should show Phase: Running
```

### 3. Verify Pods and Services

```bash
# Check pods in dev environment
kubectl get pods -n postgres-vdbs-dev

# Check services
kubectl get svc -n postgres-vdbs-dev

# Check secrets
kubectl get secrets -n postgres-vdbs-dev
```

### 4. Test Database Connection

```bash
# Get connection details from secret
kubectl get secret dev-vdb-postgres-secret -n postgres-vdbs-dev \
  -o jsonpath='{.data.connection-string}' | base64 -d; echo

# Port forward to database
kubectl port-forward svc/dev-vdb 5432:5432 -n postgres-vdbs-dev

# Connect using psql (in another terminal)
psql "postgresql://dev_user:dev_password_123@localhost:5432/dev_application"

# Test the connection
\l                          # List databases
\dn                         # List schemas
SELECT version();           # Check PostgreSQL version
\q                          # Quit
```

### 5. Verify Lifecycle Hooks

```bash
# Check hook execution
kubectl get jobs -n postgres-vdbs-dev

# Check hook logs
kubectl logs job/init-dev-schema-dev-vdb -n postgres-vdbs-dev

# Verify schemas were created
psql "postgresql://dev_user:dev_password_123@localhost:5432/dev_application" \
  -c "\dn"
```

## Managing Environments

### Create a New Feature Environment

```bash
# Make scripts executable (if not already done)
chmod +x scripts/*.sh

# Create a new feature environment
./scripts/create-feature-env.sh feat-789-new-api

# With custom resources
./scripts/create-feature-env.sh feat-890-performance \
  --memory-request 4Gi \
  --cpu-request 2 \
  --memory-limit 8Gi \
  --cpu-limit 4

# Monitor the new application
argocd app get postgres-vdb-feat-789-new-api --watch

# Check VDB status
kubectl get postgresvdb -n postgres-vdbs-feature-feat-789-new-api
```

### Cleanup a Feature Environment

```bash
# Cleanup feature environment
./scripts/cleanup-feature-env.sh feat-789-new-api

# Force cleanup without confirmation
./scripts/cleanup-feature-env.sh feat-789-new-api --force

# Watch deletion progress
kubectl get namespace postgres-vdbs-feature-feat-789-new-api -w
```

### Manual Environment Deployment

```bash
# Deploy using Helm directly (for testing)
helm install dev-test ./charts/postgres-vdb \
  -f environments/dev.yaml \
  -n postgres-vdbs-dev-test \
  --create-namespace

# Check deployment
kubectl get postgresvdb -n postgres-vdbs-dev-test

# Cleanup
helm uninstall dev-test -n postgres-vdbs-dev-test
kubectl delete namespace postgres-vdbs-dev-test
```

### Update Environment Configuration

```bash
# Edit environment values
vim environments/dev.yaml

# Commit and push changes
git add environments/dev.yaml
git commit -m "Update dev environment resources"
git push origin main

# ArgoCD will automatically sync (if auto-sync is enabled)
# Or sync manually
argocd app sync postgres-vdb-dev
```

## Troubleshooting

### VDB Not Provisioning

**Symptoms**: VDB stays in "Pending" or "Provisioning" phase

**Diagnosis**:
```bash
# Check VDB events
kubectl describe postgresvdb <vdb-name> -n <namespace>

# Check operator logs
kubectl logs -n postgres-vdb-operator \
  -l app=postgres-vdb-operator --tail=100

# Check for resource constraints
kubectl top nodes
kubectl top pods -n <namespace>
```

**Common Fixes**:
1. Verify source database reference is correct
2. Check network connectivity to Delphix DCT
3. Ensure sufficient cluster resources
4. Verify storage class is available

### ArgoCD Sync Failures

**Symptoms**: Application shows "OutOfSync" or "Failed"

**Diagnosis**:
```bash
# Get application status
argocd app get <app-name>

# Check sync operation details
argocd app get <app-name> --show-operation

# View detailed logs
argocd app logs <app-name>
```

**Common Fixes**:
```bash
# Force refresh from Git
argocd app get <app-name> --refresh

# Hard refresh (clear cache)
argocd app get <app-name> --hard-refresh

# Force sync
argocd app sync <app-name> --force

# Prune and sync
argocd app sync <app-name> --prune
```

### Database Connection Issues

**Symptoms**: Cannot connect to database

**Diagnosis**:
```bash
# Check service and endpoints
kubectl get svc,endpoints -n <namespace>

# Check pod status
kubectl get pods -n <namespace>

# Check database logs
kubectl logs <vdb-pod> -c postgres -n <namespace>

# Test connectivity from within cluster
kubectl run -it --rm debug --image=postgres:16.9 \
  --restart=Never -- psql "postgresql://user:pass@host:5432/db"
```

**Common Fixes**:
1. Verify service is created
2. Check firewall rules / network policies
3. Verify credentials in secret
4. Check PostgreSQL logs for errors

### Hook Failures

**Symptoms**: Hooks fail to execute or complete

**Diagnosis**:
```bash
# List jobs
kubectl get jobs -n <namespace>

# Check job status
kubectl describe job <hook-job-name> -n <namespace>

# View hook logs
kubectl logs job/<hook-job-name> -n <namespace>
```

**Common Fixes**:
1. Verify SQL syntax in hook script
2. Check database is ready before hook execution
3. Verify permissions for database user
4. Increase backoffLimit if transient failures

### Performance Issues

**Symptoms**: Slow database performance

**Diagnosis**:
```bash
# Check resource usage
kubectl top pods -n <namespace>

# Check PostgreSQL stats
psql -c "SELECT * FROM pg_stat_activity;"
psql -c "SELECT * FROM pg_stat_database;"

# Review slow queries
kubectl logs <vdb-pod> -n <namespace> | grep "duration:"
```

**Common Fixes**:
1. Increase resource requests/limits
2. Tune PostgreSQL configuration parameters
3. Add indexes for frequently queried tables
4. Enable connection pooling

### Namespace Stuck in Terminating

**Symptoms**: Namespace won't delete

**Diagnosis**:
```bash
# Check namespace status
kubectl get namespace <namespace> -o yaml

# Check for remaining resources
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>
```

**Fix**:
```bash
# Force delete finalizers
kubectl get namespace <namespace> -o json \
  | jq '.spec.finalizers = []' \
  | kubectl replace --raw "/api/v1/namespaces/<namespace>/finalize" -f -
```

## Advanced Configuration

### Using Secrets for Passwords

For production environments, use Kubernetes secrets instead of plain text passwords:

```bash
# Create secret
kubectl create secret generic postgres-prod-credentials \
  --from-literal=password=$(openssl rand -base64 16) \
  -n postgres-vdbs-prod

# Update values to reference secret
# In environments/values-prod.yaml:
# vdb:
#   database:
#     passwordSecret:
#       name: postgres-prod-credentials
#       key: password
```

### Enabling Monitoring

```bash
# Ensure Prometheus Operator is installed
kubectl get crd servicemonitors.monitoring.coreos.com

# Enable monitoring in values file
# monitoring:
#   enabled: true
#   serviceMonitor:
#     enabled: true
```

### Custom PostgreSQL Configuration

Add custom PostgreSQL settings in environment values:

```yaml
vdb:
  postgresConfig:
    - name: "max_connections"
      value: "500"
    - name: "shared_buffers"
      value: "2GB"
    # Add more parameters as needed
```

## Next Steps

1. **Set up monitoring**: Configure Prometheus and Grafana for VDB metrics
2. **Implement backup strategy**: Configure regular backups for critical environments
3. **Set up alerts**: Configure ArgoCD notifications for sync failures
4. **Create CI/CD pipeline**: Automate environment creation/deletion
5. **Document runbooks**: Create operational procedures for common tasks

## Support and Resources

- **Project Repository**: https://github.com/your-org/vdb-platform
- **ArgoCD Documentation**: https://argo-cd.readthedocs.io/
- **Delphix Documentation**: https://docs.delphix.com/
- **PostgreSQL Documentation**: https://www.postgresql.org/docs/

## Appendix

### Useful Commands

```bash
# Watch all VDBs
watch kubectl get postgresvdb --all-namespaces

# Watch ArgoCD applications
watch argocd app list

# Tail operator logs
kubectl logs -f -n postgres-vdb-operator -l app=postgres-vdb-operator

# Execute SQL in VDB
kubectl exec -it <vdb-pod> -n <namespace> -- \
  psql -U <user> -d <database> -c "SELECT version();"

# Backup database (example)
kubectl exec <vdb-pod> -n <namespace> -- \
  pg_dump -U <user> <database> > backup.sql
```

### Quick Reference

| Command | Description |
|---------|-------------|
| `argocd app list` | List all ArgoCD applications |
| `argocd app get <name>` | Get application details |
| `argocd app sync <name>` | Sync application |
| `kubectl get postgresvdb -A` | List all VDBs |
| `./scripts/create-feature-env.sh <name>` | Create feature environment |
| `./scripts/cleanup-feature-env.sh <name>` | Delete feature environment |

---

**Last Updated**: November 24, 2025  
**Version**: 1.0.0
