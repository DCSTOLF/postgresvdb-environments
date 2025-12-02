# Backstage Integration

This directory contains Backstage integration files for self-service PostgreSQL VDB environment creation.

## Files

- **`catalog-info.yaml`** (root) - Registers existing VDB environments in Backstage catalog
- **`backstage-templates/template.yaml`** - Software template for creating new environments
- **`backstage-templates/skeleton/`** - Template files that generate new environment configurations

## Setup Steps

### 1. Register the Catalog

Import the existing environments into Backstage:

1. Go to https://backstage.k8s.delphixdemo.com/catalog-import
2. Enter: `https://github.com/DCSTOLF/postgresvdb-environments/blob/main/catalog-info.yaml`
3. Click "Analyze" → "Import"

This will register:
- **postgres-vdb-platform** (Component) - The GitOps platform
- **postgres-vdb-dev** (Resource) - Development database
- **postgres-vdb-qa** (Resource) - QA database
- **postgres-vdb-feat-123** (Resource) - Feature branch database

### 2. Register the Template

Register the software template for creating new environments:

1. Go to https://backstage.k8s.delphixdemo.com/catalog-import
2. Enter: `https://github.com/DCSTOLF/postgresvdb-environments/blob/main/backstage-templates/template.yaml`
3. Click "Analyze" → "Import"

This creates a form at: https://backstage.k8s.delphixdemo.com/create

### 3. Configure GitHub Integration (if needed)

The template uses `publish:github:pull-request` action which requires:

1. GitHub App or Personal Access Token configured in Backstage
2. Permissions to create branches and pull requests in the repository

Check your Backstage `app-config.yaml`:

```yaml
integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}
```

## Using the Template

### Create a New Environment

1. Visit https://backstage.k8s.delphixdemo.com/create
2. Select "Create PostgreSQL VDB Environment"
3. Fill out the form:
   - **Environment Name**: e.g., `staging`, `prod`, `feat-new-api`
   - **Environment Type**: development, qa, staging, production, or feature
   - **Database Config**: name, user, password
   - **Resources**: memory/CPU requests and limits
   - **PostgreSQL Settings**: max connections, shared buffers
   - **Service Options**: enable public access, monitoring
4. Click "Create"

### What Happens

The template will:

1. ✅ Generate a new `environments/{name}/values.yaml` file
2. ✅ Create a GitHub Pull Request with:
   - New environment configuration
   - Resource specifications
   - PostgreSQL tuning parameters
3. ✅ Register the new environment in Backstage catalog

After the PR is merged:

4. ✅ ArgoCD ApplicationSet automatically detects the new directory
5. ✅ Creates `postgres-vdb-{name}` ArgoCD Application
6. ✅ Deploys the VDB to namespace `postgres-vdbs-{name}`
7. ✅ Delphix operator provisions the database

## Example Workflow

```bash
# 1. User fills Backstage form
Environment Name: staging
Type: staging
Memory: 4Gi / 8Gi
CPU: 2 / 4
Public Access: true

# 2. Backstage creates PR
Branch: add-environment-staging
Files: environments/staging/values.yaml

# 3. Review & Merge PR
git checkout add-environment-staging
# Review the generated values.yaml
git merge add-environment-staging

# 4. ArgoCD auto-deploys
Application: postgres-vdb-staging
Namespace: postgres-vdbs-staging
Service: staging-vdb (ClusterIP)
Service: staging-vdb-public (LoadBalancer)

# 5. Access the database
kubectl get svc -n postgres-vdbs-staging
```

## Customizing the Template

### Add More Parameters

Edit `backstage-templates/template.yaml` to add fields:

```yaml
parameters:
  - title: Advanced Settings
    properties:
      enableBackups:
        title: Enable Automated Backups
        type: boolean
        default: false
```

### Modify Generated Files

Edit `backstage-templates/skeleton/values.yaml` to change the generated configuration:

```yaml
# Add custom sections
backup:
  enabled: ${{ values.enableBackups }}
  schedule: "0 2 * * *"
```

### Add Multiple Files

Create additional files in `skeleton/`:

```
backstage-templates/skeleton/
├── values.yaml
├── README.md
└── .gitkeep
```

## Troubleshooting

### Template Not Showing

- Verify the template.yaml is registered in Backstage catalog
- Check Backstage logs for template validation errors
- Ensure the `scaffolder.backstage.io/v1beta3` API version is supported

### PR Creation Fails

- Verify GitHub integration is configured
- Check GitHub token has `repo` scope
- Ensure the GitHub App has write access to the repository

### ArgoCD Not Detecting New Environment

- Verify the directory structure: `environments/{name}/values.yaml`
- Check ApplicationSet path regex: `^environments/(dev|qa|stage|prod|feat-[a-zA-Z0-9-]+)$`
- Sync the ApplicationSet: `argocd app sync postgres-vdb-platform --grpc-web`

## Resources

- [Backstage Software Templates](https://backstage.io/docs/features/software-templates/)
- [Backstage Catalog](https://backstage.io/docs/features/software-catalog/)
- [Template Actions](https://backstage.io/docs/features/software-templates/builtin-actions/)
