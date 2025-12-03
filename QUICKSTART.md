# Quick Start Guide

This is a quick reference for common operations. For detailed instructions, see [README.md](README.md).

## Prerequisites Check

```bash
make check-tools
```

## Initial Setup

```bash
# 1. Validate configuration
make validate

# 2. Deploy ArgoCD ApplicationSet
kubectl apply -f applications/postgres-vdb-appset.yaml -n argocd

# 3. Verify ApplicationSet is running
argocd appset list --grpc-web
```

## Two Ways to Create Environments

### Option 1: Self-Service via Backstage (Recommended)

1. Visit https://backstage.k8s.delphixdemo.com/create
2. Select "PostgreSQL VDB Environment" template
3. Fill in the form with your environment details
4. Template creates a PR with the new environment
5. Merge the PR
6. ArgoCD automatically detects and deploys the environment

See [BACKSTAGE_QUICKSTART.md](BACKSTAGE_QUICKSTART.md) for detailed Backstage usage.

### Option 2: Manual Creation via Makefile

```bash
# Create a new environment (staging, prod, etc.)
make create-env ENV=staging

# Or create a feature environment
make create-feature FEATURE=feat-789-new-api
```

This creates `environments/{name}/values.yaml` - customize it, then commit and push to trigger deployment.

## Environment Management

### List Active Environments

```bash
# View all environments via ArgoCD
argocd app list --grpc-web | grep postgres-vdb

# View all VDB resources
kubectl get postgresvdb -A

# View environment directories
ls -la environments/
```

### Deploy Specific Environment (Manual)

```bash
# Using Helm directly (bypasses ArgoCD)
make install-env ENV=dev

# Or sync via ArgoCD (recommended)
argocd app sync postgres-vdb-dev --grpc-web
```

### Delete Environment (Complete Cleanup)

```bash
# Delete any environment (with safety confirmation)
make delete-env ENV=staging

# Delete feature environment
make cleanup-feature FEATURE=feat-789-new-api
```

**What happens during deletion:**
1. Warns and waits 5 seconds for confirmation
2. Deletes ArgoCD app with `--cascade` flag
3. Waits 10 seconds for cascade cleanup
4. Force deletes VDB if still present
5. Force deletes namespace if stuck
6. Removes `environments/{name}/` directory
7. Shows next steps (commit/push, verify)

See [README.md - Deleting Environments](README.md#deleting-environments) for detailed deletion procedures.

## Monitoring

### View All VDBs

```bash
make list-vdbs
# Or directly:
kubectl get postgresvdb -A
```

### View ArgoCD Applications

```bash
make list-apps
# Or directly:
argocd app list --grpc-web
```

### View Overall Status

```bash
make status
```

### View Specific Environment Details

```bash
# VDB status
kubectl describe postgresvdb {env-name}-vdb -n postgres-vdbs-{env-name}

# Pod status
kubectl get pods -n postgres-vdbs-{env-name}

# ArgoCD app status
argocd app get postgres-vdb-{env-name} --grpc-web
```

### View Logs

```bash
# Specific environment logs
kubectl logs -n postgres-vdbs-dev -l app.kubernetes.io/instance=dev-vdb --tail=100 -f

# Or use make for dev
make logs-dev

# Operator logs (if available)
make logs-operator
```

## Database Connection

### Port Forward to Dev Database

```bash
make connect-dev
```

Then in another terminal:
```bash
psql -h localhost -p 5432 -U dev_user -d dev_application
```

### Test Connection (from within cluster)

```bash
make test-connection
```

## Development Workflow

### Preview Changes (Helm Template)

```bash
# Specific environment
make template-env ENV=dev

# Dev environment (shorthand)
make template

# All environments
make template-all
```

### View Diff (requires helm-diff plugin)

```bash
make diff
```

### Validate Changes

```bash
make validate
```

### GitOps Workflow

1. Create/modify environment: `environments/{name}/values.yaml`
2. Commit and push changes
3. ArgoCD detects changes automatically (Git polling)
4. ArgoCD syncs and deploys to Kubernetes
5. Monitor: `argocd app get postgres-vdb-{name} --grpc-web`

## Common Tasks

| Task | Command |
|------|---------|
| List all VDBs | `kubectl get postgresvdb -A` |
| List ArgoCD apps | `argocd app list --grpc-web` |
| Describe a VDB | `kubectl describe postgresvdb {name}-vdb -n postgres-vdbs-{name}` |
| View VDB logs | `kubectl logs -n postgres-vdbs-{name} -l app.kubernetes.io/instance={name}-vdb` |
| Sync ArgoCD app | `argocd app sync postgres-vdb-{name} --grpc-web` |
| Template environment | `make template-env ENV={name}` |
| Create environment | `make create-env ENV={name}` |
| Delete environment | `make delete-env ENV={name}` |
| View all environments | `ls -la environments/` |
| Check status | `make status` |

## Troubleshooting Quick Reference

### VDB Not Starting

```bash
# Check VDB resource status
kubectl describe postgresvdb {name}-vdb -n postgres-vdbs-{name}

# Check events
kubectl get events -n postgres-vdbs-{name} --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -n postgres-vdbs-{name} -l app.kubernetes.io/instance={name}-vdb
```

### ArgoCD Sync Issues

```bash
# Get app details
argocd app get postgres-vdb-{name} --grpc-web

# Force sync
argocd app sync postgres-vdb-{name} --grpc-web --force

# Check ApplicationSet
argocd appset get postgres-vdb-platform --grpc-web
```

### Environment Not Appearing in ArgoCD

1. Check directory structure: `ls -la environments/{name}/`
2. Ensure `values.yaml` exists in the directory
3. Verify path matches regex: `environments/(dev|qa|stage|prod|feat-[a-zA-Z0-9-]+)/`
4. Check ApplicationSet status: `kubectl get appset -n argocd postgres-vdb-platform -o yaml`
5. Force ApplicationSet refresh: `kubectl annotate appset -n argocd postgres-vdb-platform argocd.argoproj.io/refresh=now --overwrite`

### Deletion Issues - Resources Stuck

```bash
# If VDB is stuck in Terminating state
kubectl patch postgresvdb {name}-vdb -n postgres-vdbs-{name} -p '{"metadata":{"finalizers":[]}}' --type=merge

# If namespace is stuck
kubectl get namespace postgres-vdbs-{name} -o json | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/postgres-vdbs-{name}/finalize -f -

# Force delete everything
kubectl delete postgresvdb --all -n postgres-vdbs-{name} --force --grace-period=0
kubectl delete namespace postgres-vdbs-{name} --force --grace-period=0
```

## Configuration Files

- **Helm Chart**: `charts/postgres-vdb/`
  - `values.yaml` - Default values/template
  - `templates/` - Kubernetes manifests
- **Environments**: `environments/{name}/`
  - `environments/dev/values.yaml` - Development
  - `environments/qa/values.yaml` - QA
  - `environments/feat-123/values.yaml` - Feature branches
- **ArgoCD**: `applications/`
  - `postgres-vdb-appset.yaml` - ApplicationSet with Git generator
- **Backstage**: `backstage-templates/`
  - `template.yaml` - Self-service template
  - `skeleton/values.yaml` - Template for generated environments
- **Catalog**: `catalog-info.yaml` - Backstage catalog entities

## Project Architecture

```
environments/
├── dev/
│   └── values.yaml          # Dev environment config
├── qa/
│   └── values.yaml          # QA environment config
├── feat-123/
│   └── values.yaml          # Feature environment config
└── [your-env]/
    └── values.yaml          # Your environment config

applications/
└── postgres-vdb-appset.yaml # ArgoCD ApplicationSet

charts/postgres-vdb/
├── Chart.yaml
├── values.yaml              # Default/template values
└── templates/
    ├── postgresvdb.yaml     # VDB custom resource
    ├── service.yaml         # K8s service
    └── ...

backstage-templates/
├── template.yaml            # Backstage Software Template
└── skeleton/
    └── values.yaml          # Jinja2 template
```

## How It Works

1. **GitOps Flow**:
   - `environments/{name}/values.yaml` files define each environment
   - ArgoCD ApplicationSet watches `environments/*/` directories
   - Changes to values.yaml trigger automatic deployment
   - Each environment gets its own namespace: `postgres-vdbs-{name}`

2. **Self-Service Flow** (Backstage):
   - User fills out template form at `/create`
   - Template generates PR with new `environments/{name}/values.yaml`
   - User reviews and merges PR
   - ArgoCD detects new directory and creates Application
   - VDB is provisioned automatically

## Important Notes

⚠️ **Security**: Always change default passwords before deployment! Use Kubernetes Secrets for production.

⚠️ **ArgoCD CLI**: All `argocd` commands require the `--grpc-web` flag for this cluster.

⚠️ **Deletion**: Always use `--cascade` flag when deleting ArgoCD apps:
```bash
argocd app delete postgres-vdb-{name} --grpc-web --cascade --yes
```

⚠️ **Git Repository**: Ensure the repository URL in `postgres-vdb-appset.yaml` is correct.

⚠️ **Source Database**: Configure Delphix DCT source in environment `values.yaml` files.

⚠️ **Environment Naming**: Follow the regex pattern for auto-discovery:
- Allowed: `dev`, `qa`, `stage`, `prod`, `feat-123`, `feat-new-api`
- Not allowed: `feature-123`, `test`, `demo` (unless regex is updated)

## Quick Command Reference

```bash
# Setup
make check-tools                           # Verify prerequisites
kubectl apply -f applications/postgres-vdb-appset.yaml -n argocd

# Create environments
make create-env ENV=staging                # Via Makefile
# Or use Backstage UI                      # Via Backstage

# Monitor
make status                                # Overall status
argocd app list --grpc-web                # ArgoCD apps
kubectl get postgresvdb -A                # All VDBs
kubectl get pods -n postgres-vdbs-{name}  # Specific environment

# Delete
make delete-env ENV=staging                # Complete cleanup
make cleanup-feature FEATURE=feat-123     # Feature cleanup

# Verify deletion
argocd app list --grpc-web | grep {name}
kubectl get all -n postgres-vdbs-{name}
ls -la environments/
```

## Next Steps

After initial setup:

1. **Try Self-Service**: Create an environment via Backstage at `/create`
2. **Configure Monitoring**: Set up Prometheus/Grafana for VDB metrics
3. **Set Up Backups**: Configure backup strategies for critical environments
4. **CI/CD Integration**: Add automated testing in your pipelines
5. **Access Control**: Configure RBAC for ArgoCD and Backstage
6. **Notifications**: Set up ArgoCD notifications (Slack, email, etc.)
7. **Cost Tracking**: Add labels/tags for cost allocation
8. **Documentation**: Document team-specific procedures

## Resources

- **Main Documentation**: [README.md](README.md) - Complete guide with architecture and operations
- **Backstage Guide**: [BACKSTAGE_QUICKSTART.md](BACKSTAGE_QUICKSTART.md) - Self-service provisioning
- **ArgoCD Docs**: https://argo-cd.readthedocs.io/
- **Helm Docs**: https://helm.sh/docs/
- **Backstage Docs**: https://backstage.io/docs/

## Support

For issues or questions:
1. Check troubleshooting sections in [README.md](README.md)
2. Review [BACKSTAGE_QUICKSTART.md](BACKSTAGE_QUICKSTART.md) for template issues
3. Check ArgoCD app status: `argocd app get postgres-vdb-{name} --grpc-web`
4. Review Kubernetes events: `kubectl get events -n postgres-vdbs-{name}`
