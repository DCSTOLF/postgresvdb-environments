# PostgreSQL VDB Environment Management with ArgoCD

## Overview

This project manages dynamic PostgreSQL Virtual Database (VDB) environments using ArgoCD and a custom Kubernetes operator. It enables automated provisioning of database environments (dev, qa, feature branches) through GitOps workflows.

## Architecture

```
ArgoCD → Helm Charts → PostgresVDB Operator → PostgreSQL VDB Instances
```

## Prerequisites

- Kubernetes cluster (v1.24+)
- ArgoCD installed
- PostgresVDB operator installed
- Helm (v3.8+)
- kubectl

## Project Structure

```
vdb-platform/
├── charts/
│   └── postgres-vdb/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── .helmignore
│       └── templates/
│           ├── postgresvdb.yaml
│           ├── hooks.yaml
│           ├── secrets.yaml
│           └── _helpers.tpl
├── environments/
│   ├── dev.yaml
│   ├── qa.yaml
│   ├── values-prod.yaml
│   └── features/
│       ├── feat-123.yaml
│       └── feat-456.yaml
├── applications/
│   ├── app-of-apps.yaml
│   ├── applicationset-environments.yaml
│   └── applicationset-features.yaml
└── scripts/
    ├── create-feature-env.sh
    └── cleanup-feature-env.sh
```

## Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/your-org/vdb-platform.git
cd vdb-platform
```

### 2. Install PostgresVDB Operator

```bash
kubectl apply -f https://raw.githubusercontent.com/delphix/operator/main/deploy/crds/core.delphix.com_postgresvdbs.yaml
kubectl apply -f https://raw.githubusercontent.com/delphix/operator/main/deploy/operator.yaml
```

### 3. Deploy Base Configuration

```bash
# Create namespace
kubectl create namespace postgres-vdbs

# Deploy ArgoCD Application of Applications
kubectl apply -f applications/app-of-apps.yaml -n argocd
```

## Helm Chart Configuration

### Chart.yaml

```yaml
apiVersion: v2
name: postgres-vdb
description: Dynamic PostgreSQL VDB Environments
type: application
version: 0.1.0
appVersion: "1.0.0"

dependencies:
  - name: postgres-vdb-operator
    version: "0.1.0"
    repository: "https://charts.delphix.com/"

annotations:
  helm.sh/hook-weight: "-5"
```

### values.yaml (Base Configuration)

```yaml
global:
  # Source database configuration
  sourceDatabase: "10.0.1.54:largedb"
  postgresImage: "postgres:16.9"
  storageClass: "de-fs-storage"
  
  # Default resource limits
  defaultResources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1"

# VDB configuration
vdb:
  enabled: true
  port: 5432
  mountPath: "/mnt/postgres"
  ownershipSpec: "999:999"
  mode: "Primary"
  errorBackoffPeriod: "5m"
  
  # Database credentials (override per environment)
  database:
    name: "postgres"
    user: "postgres"
    password: "changeme123"
  
  # Resource configuration
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1"
  
  # Lifecycle hooks
  hooks: []
  
  # PostgreSQL configuration
  postgresConfig:
    - name: "shared_buffers"
      value: "256MB"
    - name: "max_connections"
      value: "100"

# Operator configuration
operator:
  enabled: true
  image:
    repository: "delphix/postgres-vdb-operator"
    tag: "latest"
  
# Monitoring configuration
monitoring:
  enabled: false
  serviceMonitor:
    enabled: false
```

### Environment-Specific Values

#### dev.yaml

```yaml
environment: dev

vdb:
  name: "dev-vdb"
  database:
    name: "dev_application"
    user: "dev_user"
    password: "dev_password_123"
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
  hooks:
    - name: "init-dev-schema"
      stage: "post-create"
      database: "dev_application"
      script: |
        CREATE SCHEMA IF NOT EXISTS dev_features;
        CREATE SCHEMA IF NOT EXISTS dev_testing;
        GRANT USAGE ON SCHEMA dev_features TO dev_user;
        GRANT USAGE ON SCHEMA dev_testing TO dev_user;
```

#### qa.yaml

```yaml
environment: qa

vdb:
  name: "qa-vdb"
  database:
    name: "qa_application"
    user: "qa_user"
    password: "qa_password_123"
  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
  hooks:
    - name: "init-qa-schema"
      stage: "post-create"
      database: "qa_application"
      script: |
        CREATE SCHEMA IF NOT EXISTS qa_testing;
        CREATE TABLE qa_testing.test_results (
          test_id SERIAL PRIMARY KEY,
          test_name VARCHAR(100),
          result BOOLEAN,
          executed_at TIMESTAMP DEFAULT NOW()
        );
```

#### feat-123.yaml

```yaml
environment: feature
featureBranch: "feat-123"

vdb:
  name: "feat-123-vdb"
  database:
    name: "feat_123_app"
    user: "feat_123_user"
    password: "feat_123_password"
  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
    limits:
      memory: "4Gi"
      cpu: "2"
  hooks:
    - name: "init-feat-schema"
      stage: "post-create"
      database: "feat_123_app"
      script: |
        CREATE SCHEMA IF NOT EXISTS feat_123_experimental;
        CREATE TABLE feat_123_experimental.experimental_data (
          id SERIAL PRIMARY KEY,
          feature_data JSONB,
          created_at TIMESTAMP DEFAULT NOW()
        );
        GRANT ALL ON SCHEMA feat_123_experimental TO feat_123_user;
        GRANT ALL ON ALL TABLES IN SCHEMA feat_123_experimental TO feat_123_user;
```

## Template Files

### templates/postgresvdb.yaml

```yaml
{{- if .Values.vdb.enabled }}
apiVersion: core.delphix.com/v1alpha1
kind: PostgresVDB
metadata:
  name: {{ .Values.vdb.name | default .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "postgres-vdb.labels" . | nindent 4 }}
    environment: {{ .Values.environment | default "development" }}
    {{- if .Values.featureBranch }}
    feature-branch: {{ .Values.featureBranch }}
    {{- end }}
  annotations:
    "argocd.argoproj.io/sync-wave": "{{ .Values.syncWave | default "0" }}"
spec:
  source:
    type: dct-source
    reference: {{ .Values.global.sourceDatabase }}
  port: {{ .Values.vdb.port }}
  image: {{ .Values.global.postgresImage }}
  mountPath: {{ .Values.vdb.mountPath }}
  ownershipSpec: {{ .Values.vdb.ownershipSpec }}
  mode: {{ .Values.vdb.mode }}
  errorBackoffPeriod: {{ .Values.vdb.errorBackoffPeriod }}
  enabled: {{ .Values.vdb.enabled }}
  
  {{- if .Values.vdb.database }}
  database:
    name: {{ .Values.vdb.database.name }}
    user: {{ .Values.vdb.database.user }}
    password: {{ .Values.vdb.database.password }}
  {{- end }}
  
  {{- if .Values.vdb.resources }}
  resources:
    requests:
      memory: {{ .Values.vdb.resources.requests.memory }}
      cpu: {{ .Values.vdb.resources.requests.cpu }}
    {{- if .Values.vdb.resources.limits }}
    limits:
      memory: {{ .Values.vdb.resources.limits.memory }}
      cpu: {{ .Values.vdb.resources.limits.cpu }}
    {{- end }}
  {{- end }}
  
  {{- if .Values.vdb.postgresConfig }}
  postgresConfig:
    {{- toYaml .Values.vdb.postgresConfig | nindent 4 }}
  {{- end }}
  
  {{- if .Values.vdb.hooks }}
  hooks:
    {{- toYaml .Values.vdb.hooks | nindent 4 }}
  {{- end }}
{{- end }}
```

### templates/hooks.yaml

```yaml
{{- if .Values.vdb.hooks }}
{{- range .Values.vdb.hooks }}
{{- if eq .type "command" | default false }}
---
apiVersion: batch/v1
kind: Job
metadata:
  name: "{{ .name }}-{{ $.Release.Name }}"
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "{{ .weight | default "5" }}"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
  labels:
    {{- include "postgres-vdb.labels" $ | nindent 4 }}
    hook: {{ .name }}
spec:
  template:
    spec:
      containers:
      - name: hook-executor
        image: {{ $.Values.global.postgresImage }}
        command: ["/bin/sh", "-c"]
        args:
        - |
          psql "postgresql://{{ $.Values.vdb.database.user }}:{{ $.Values.vdb.database.password }}@{{ $.Release.Name }}:{{ $.Values.vdb.port }}/{{ .database | default $.Values.vdb.database.name }}" -c "{{ .script }}"
        env:
        - name: PGPASSWORD
          value: {{ $.Values.vdb.database.password }}
      restartPolicy: OnFailure
      backoffLimit: 3
{{- end }}
{{- end }}
{{- end }}
```

### templates/_helpers.tpl

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "postgres-vdb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "postgres-vdb.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "postgres-vdb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "postgres-vdb.labels" -}}
helm.sh/chart: {{ include "postgres-vdb.chart" . }}
{{ include "postgres-vdb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "postgres-vdb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres-vdb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "postgres-vdb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "postgres-vdb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
```

## ArgoCD Configuration

### Application of Applications

**applications/app-of-apps.yaml**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: postgres-vdb-platform
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/vdb-platform.git
    targetRevision: main
    path: applications
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### Environment ApplicationSet

**applications/applicationset-environments.yaml**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: postgres-vdb-environments
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/your-org/vdb-platform.git
      revision: main
      directories:
      - path: environments/*
  
  template:
    metadata:
      name: "postgres-vdb-{{path.basename}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/vdb-platform.git
        targetRevision: main
        chart: charts/postgres-vdb
        helm:
          valueFiles:
          - "../../environments/{{path.basename}}/values.yaml"
          parameters:
          - name: global.environment
            value: "{{path.basename}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: postgres-vdbs-{{path.basename}}
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
      info:
        - name: description
          value: "PostgreSQL VDB for {{path.basename}} environment"
```

### Feature Branch ApplicationSet

**applications/applicationset-features.yaml**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: postgres-vdb-features
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/your-org/vdb-platform.git
      revision: main
      directories:
      - path: environments/features/*
  
  template:
    metadata:
      name: "postgres-vdb-{{path.basename}}"
      annotations:
        argocd.argoproj.io/sync-wave: "1"
    spec:
      project: features
      source:
        repoURL: https://github.com/your-org/vdb-platform.git
        targetRevision: main
        chart: charts/postgres-vdb
        helm:
          valueFiles:
          - "../../environments/features/{{path.basename}}/values.yaml"
          parameters:
          - name: global.environment
            value: "feature"
          - name: featureBranch
            value: "{{path.basename}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: postgres-vdbs-feature-{{path.basename}}
      syncPolicy:
        automated:
          prune: true
          selfHeal: false  # Manual cleanup for feature branches
        syncOptions:
        - CreateNamespace=true
      info:
        - name: description
          value: "PostgreSQL VDB for feature branch {{path.basename}}"
```

## Automation Scripts

### Create Feature Environment

**scripts/create-feature-env.sh**

```bash
#!/bin/bash

set -e

FEATURE_NAME=$1
if [ -z "$FEATURE_NAME" ]; then
    echo "Usage: $0 <feature-name>"
    exit 1
fi

# Create values file for feature branch
cat > "environments/features/values-${FEATURE_NAME}.yaml" << EOF
environment: feature
featureBranch: "${FEATURE_NAME}"

vdb:
  name: "${FEATURE_NAME}-vdb"
  database:
    name: "${FEATURE_NAME}_app"
    user: "${FEATURE_NAME}_user"
    password: "$(openssl rand -base64 16)"
  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
    limits:
      memory: "4Gi"
      cpu: "2"
  hooks:
    - name: "init-${FEATURE_NAME}-schema"
      stage: "post-create"
      database: "${FEATURE_NAME}_app"
      script: |
        CREATE SCHEMA IF NOT EXISTS ${FEATURE_NAME}_experimental;
        GRANT ALL ON SCHEMA ${FEATURE_NAME}_experimental TO ${FEATURE_NAME}_user;
EOF

echo "Created feature environment configuration for ${FEATURE_NAME}"
echo "File: environments/features/values-${FEATURE_NAME}.yaml"

# Commit and push to trigger ArgoCD
git add "environments/features/values-${FEATURE_NAME}.yaml"
git commit -m "Add feature environment for ${FEATURE_NAME}"
git push origin main

echo "Feature environment ${FEATURE_NAME} will be provisioned automatically by ArgoCD"
```

### Cleanup Feature Environment

**scripts/cleanup-feature-env.sh**

```bash
#!/bin/bash

set -e

FEATURE_NAME=$1
if [ -z "$FEATURE_NAME" ]; then
    echo "Usage: $0 <feature-name>"
    exit 1
fi

# Remove values file
rm -f "environments/features/values-${FEATURE_NAME}.yaml"

# Commit and push to trigger cleanup
git add "environments/features/values-${FEATURE_NAME}.yaml"
git commit -m "Remove feature environment for ${FEATURE_NAME}"
git push origin main

echo "Feature environment ${FEATURE_NAME} will be cleaned up automatically by ArgoCD"
```

## Usage Examples

### Manual Helm Deployment

```bash
# Deploy development environment
helm install dev-vdb ./charts/postgres-vdb -f environments/dev.yaml -n postgres-vdbs-dev

# Deploy QA environment  
helm install qa-vdb ./charts/postgres-vdb -f environments/qa.yaml -n postgres-vdbs-qa

# Upgrade with new resources
helm upgrade dev-vdb ./charts/postgres-vdb -f environments/dev.yaml --set vdb.resources.requests.memory=2Gi -n postgres-vdbs-dev

# Check status
helm list -n postgres-vdbs-dev
kubectl get postgresvdbs -n postgres-vdbs-dev
```

### Create Feature Branch Environment

```bash
# Make script executable
chmod +x scripts/create-feature-env.sh

# Create feature environment
./scripts/create-feature-env.sh feat-123-new-ui

# Check ArgoCD application
argocd app get postgres-vdb-feat-123-new-ui

# Check VDB status
kubectl get postgresvdb -n postgres-vdbs-feature-feat-123-new-ui
```

### Database Connection

```bash
# Get connection details
kubectl get postgresvdb dev-vdb -n postgres-vdbs-dev -o jsonpath='{.status.connectionString}'

# Port forward for local access
kubectl port-forward svc/dev-vdb 5432:5432 -n postgres-vdbs-dev

# Connect using psql
psql -h localhost -p 5432 -U dev_user -d dev_application
```

## Monitoring and Troubleshooting

### Check VDB Status

```bash
# List all VDBs across namespaces
kubectl get postgresvdbs --all-namespaces

# Check specific VDB status
kubectl describe postgresvdb dev-vdb -n postgres-vdbs-dev

# Check operator logs
kubectl logs -l app.kubernetes.io/name=postgres-vdb-operator -n postgres-vdbs

# Check VDB pods
kubectl get pods -l app.kubernetes.io/instance=dev-vdb -n postgres-vdbs-dev
```

### ArgoCD Sync Status

```bash
# List all applications
argocd app list

# Check sync status
argocd app get postgres-vdb-dev

# Sync manually if needed
argocd app sync postgres-vdb-dev
```

## Best Practices

1. **Security**
   - Use secrets for database passwords in production
   - Implement network policies to restrict access
   - Use different namespaces per environment

2. **Resource Management**
   - Set appropriate resource requests and limits
   - Monitor database performance and storage
   - Implement cleanup policies for feature branches

3. **GitOps**
   - All changes through Git commits
   - Use PR reviews for production changes
   - Tag releases for production deployments

4. **Backup and Recovery**
   - Implement regular backups of critical data
   - Test recovery procedures
   - Use persistent volume snapshots where appropriate

## Troubleshooting Common Issues

### VDB Not Provisioning

```bash
# Check operator status
kubectl get pods -l app.kubernetes.io/name=postgres-vdb-operator

# Check VDB events
kubectl describe postgresvdb <vdb-name> -n <namespace>

# Check operator logs
kubectl logs -f <operator-pod> -n postgres-vdbs
```

### ArgoCD Sync Issues

```bash
# Check application sync status
argocd app get <app-name>

# Check sync result details
argocd app sync <app-name> --loglevel debug

# Force refresh
argocd app get <app-name> --refresh
```

### Database Connection Issues

```bash
# Check service and endpoints
kubectl get svc,endpoints -l app.kubernetes.io/instance=<vdb-name>

# Check pod status
kubectl get pods -l app.kubernetes.io/instance=<vdb-name>

# Check database logs
kubectl logs <vdb-pod> -c postgres
```

## Support

For issues and questions:
1. Check operator logs and VDB status
2. Review ArgoCD application sync status
3. Consult the PostgresVDB operator documentation
4. Open issues in the project repository

## Deleting Environments

When you need to remove a PostgreSQL VDB environment, follow these steps to ensure complete cleanup:

### Option 1: Delete via ArgoCD (Recommended)

This is the cleanest approach as it removes both the ArgoCD application and all Kubernetes resources in one command:

```bash
# Delete the environment (replace {env-name} with actual environment name: dev, qa, feat-123, etc.)
argocd app delete postgres-vdb-{env-name} --grpc-web --cascade --yes
```

**Important**: Always use the `--cascade` flag to ensure all Kubernetes resources are deleted along with the ArgoCD application.

**Example:**
```bash
# Delete the staging environment
argocd app delete postgres-vdb-stage --grpc-web --cascade --yes
```

### Option 2: Delete via Git + ArgoCD Auto-Prune

Since the ApplicationSet has `automated.prune: true`, you can delete the environment directory from git and let ArgoCD handle the cleanup automatically:

```bash
# Remove the environment directory
rm -rf environments/{env-name}

# Commit and push
git add -A
git commit -m "Remove {env-name} environment"
git push
```

ArgoCD will detect the change within ~3 minutes and automatically:
1. Delete the Application
2. Remove all Kubernetes resources
3. Delete the namespace

### Option 3: Manual Cleanup (If ArgoCD Fails)

If ArgoCD deletion doesn't clean up resources properly, manually remove them:

```bash
# 1. Delete the PostgresVDB custom resource (triggers operator cleanup)
kubectl delete postgresvdb {env-name}-vdb -n postgres-vdbs-{env-name}

# 2. Delete the namespace (removes all remaining resources)
kubectl delete namespace postgres-vdbs-{env-name}

# 3. Delete the ArgoCD Application if it still exists
kubectl delete application postgres-vdb-{env-name} -n argocd
```

### Complete Cleanup Procedure

For a thorough cleanup of an environment, follow this checklist:

1. **Delete from ArgoCD** (with cascade):
   ```bash
   argocd app delete postgres-vdb-{env-name} --grpc-web --cascade --yes
   ```

2. **Remove from Git repository**:
   ```bash
   cd /path/to/postgresvdb-environments
   rm -rf environments/{env-name}
   git add -A
   git commit -m "Remove {env-name} environment"
   git push
   ```

3. **Verify cleanup**:
   ```bash
   # Check ArgoCD application is gone
   argocd app list --grpc-web | grep {env-name}
   
   # Check namespace is deleted
   kubectl get namespace | grep postgres-vdbs-{env-name}
   
   # Check no VDB resources remain
   kubectl get postgresvdb --all-namespaces | grep {env-name}
   ```

### Troubleshooting Deletion Issues

**If namespace is stuck in "Terminating" state:**

```bash
# Check for finalizers blocking deletion
kubectl get namespace postgres-vdbs-{env-name} -o json | jq '.spec.finalizers'

# Force remove finalizers if needed
kubectl patch namespace postgres-vdbs-{env-name} -p '{"metadata":{"finalizers":[]}}' --type=merge
```

**If VDB resource won't delete:**

```bash
# Check VDB finalizers
kubectl get postgresvdb {env-name}-vdb -n postgres-vdbs-{env-name} -o json | jq '.metadata.finalizers'

# Remove finalizers if needed
kubectl patch postgresvdb {env-name}-vdb -n postgres-vdbs-{env-name} -p '{"metadata":{"finalizers":[]}}' --type=merge
```

**If ArgoCD app won't delete:**

```bash
# Check application finalizers
kubectl get application postgres-vdb-{env-name} -n argocd -o json | jq '.metadata.finalizers'

# Force delete if stuck
kubectl patch application postgres-vdb-{env-name} -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete application postgres-vdb-{env-name} -n argocd --force --grace-period=0
```

### Best Practices for Deletion

1. **Always use `--cascade`** when deleting via ArgoCD CLI to ensure resources are cleaned up
2. **Backup data first** if the environment contains important data
3. **Verify deletion** by checking ArgoCD, Kubernetes resources, and git repository
4. **Document the reason** in the git commit message when removing environments
5. **Use Git-based deletion** for production environments to maintain audit trail

### Quick Reference Commands

```bash
# Delete environment (complete cleanup)
argocd app delete postgres-vdb-{env-name} --grpc-web --cascade --yes
rm -rf environments/{env-name}
git add -A && git commit -m "Remove {env-name} environment" && git push

# Verify deletion
argocd app list --grpc-web | grep {env-name}
kubectl get namespace | grep postgres-vdbs-{env-name}
kubectl get postgresvdb --all-namespaces | grep {env-name}
```