# Quick Start: Backstage Integration

## Step 1: Register Existing Environments

Visit: https://backstage.k8s.delphixdemo.com/catalog-import

Import URL:
```
https://github.com/DCSTOLF/postgresvdb-environments/blob/main/catalog-info.yaml
```

This registers your existing `dev`, `qa`, and `feat-123` environments in the Backstage catalog.

## Step 2: Register the Template

Visit: https://backstage.k8s.delphixdemo.com/catalog-import

Import URL:
```
https://github.com/DCSTOLF/postgresvdb-environments/blob/main/backstage-templates/template.yaml
```

This enables the "Create PostgreSQL VDB Environment" form.

## Step 3: Create a New Environment

1. Visit: https://backstage.k8s.delphixdemo.com/create
2. Click "Create PostgreSQL VDB Environment"
3. Fill in:
   - Environment name: `staging`
   - Type: Staging
   - Resources: 2Gi/1CPU
   - Enable public access: Yes
4. Click "Create"

## What Happens

1. **Backstage** creates a Pull Request
2. **You review** the generated `environments/staging/values.yaml`
3. **Merge** the PR
4. **ArgoCD** detects the new directory automatically
5. **Deploys** `postgres-vdb-staging` application
6. **Delphix** provisions the database

## That's It! 🚀

Your new environment is automatically deployed via GitOps!

Check progress:
- ArgoCD: https://argocd.k8s.delphixdemo.com/applications/postgres-vdb-staging
- Backstage: https://backstage.k8s.delphixdemo.com/catalog
