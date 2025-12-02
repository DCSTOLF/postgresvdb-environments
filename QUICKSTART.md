# Quick Start Guide

This is a quick reference for common operations. For detailed instructions, see [DEPLOY.md](DEPLOY.md).

## Prerequisites Check

```bash
make check-tools
```

## Initial Setup

```bash
# 1. Validate configuration
make validate

# 2. Install CRDs
make install-crds

# 3. Deploy ArgoCD applications
make deploy-argocd-apps
```

## Environment Management

### Deploy Development Environment

```bash
# Using Helm directly
make install-dev

# Or wait for ArgoCD to sync automatically
argocd app sync postgres-vdb-dev
```

### Create Feature Environment

```bash
# Using the script
./scripts/create-feature-env.sh feat-789-new-api

# Using make
make create-feature FEATURE=feat-789-new-api
```

### Cleanup Feature Environment

```bash
# Using the script
./scripts/cleanup-feature-env.sh feat-789-new-api

# Using make
make cleanup-feature FEATURE=feat-789-new-api
```

## Monitoring

### View All VDBs

```bash
make list-vdbs
```

### View ArgoCD Applications

```bash
make list-apps
```

### View Overall Status

```bash
make status
```

### View Logs

```bash
# Operator logs
make logs-operator

# Dev environment logs
make logs-dev
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
# Dev environment
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

## Common Tasks

| Task | Command |
|------|---------|
| List all VDBs | `kubectl get postgresvdb -A` |
| Describe a VDB | `kubectl describe postgresvdb <name> -n <namespace>` |
| View VDB logs | `kubectl logs <pod-name> -n <namespace>` |
| Sync ArgoCD app | `argocd app sync <app-name>` |
| Delete environment | `helm uninstall <release> -n <namespace>` |

## Troubleshooting Quick Reference

### VDB Not Starting

```bash
kubectl describe postgresvdb <name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Check Operator Status

```bash
kubectl get pods -n postgres-vdb-operator
kubectl logs -n postgres-vdb-operator -l app=postgres-vdb-operator --tail=50
```

### ArgoCD Sync Issues

```bash
argocd app get <app-name>
argocd app sync <app-name> --force
```

## Configuration Files

- **Base Helm values**: `charts/postgres-vdb/values.yaml`
- **Dev environment**: `environments/dev.yaml`
- **QA environment**: `environments/qa.yaml`
- **Prod environment**: `environments/values-prod.yaml`
- **Feature environments**: `environments/features/values-*.yaml`

## Important Notes

⚠️ **Security**: Always change default passwords before deployment!

⚠️ **Production**: Use Kubernetes secrets for sensitive data, not plain text in values files.

⚠️ **Git Repository**: Update the repository URLs in `applications/*.yaml` files.

⚠️ **Source Database**: Configure the correct Delphix DCT source in `charts/postgres-vdb/values.yaml`.

## Next Steps

After initial setup:

1. Configure monitoring (Prometheus/Grafana)
2. Set up backup strategies
3. Configure ArgoCD notifications
4. Create CI/CD pipelines
5. Document operational procedures

## Resources

- **Full Deployment Guide**: [DEPLOY.md](DEPLOY.md)
- **Project README**: [README.md](README.md)
- **ArgoCD Docs**: https://argo-cd.readthedocs.io/
- **Helm Docs**: https://helm.sh/docs/
