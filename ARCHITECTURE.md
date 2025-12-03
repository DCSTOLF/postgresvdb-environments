# Project Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Git Repository                             │
│  ┌────────────────┬──────────────────┬────────────────────────────┐ │
│  │  Helm Charts   │  Environments    │  ArgoCD ApplicationSet     │ │
│  │  (templates)   │  (directories)   │  + Backstage Templates     │ │
│  └────────────────┴──────────────────┴────────────────────────────┘ │
└────────────────────────────────────┬────────────────────────────────┘
                                     │
                                     │ GitOps Pull (Git Directory Generator)
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            ArgoCD                                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │         ApplicationSet: postgres-vdb-platform               │   │
│  │         (Git Directory Generator)                           │   │
│  │  ┌─────────────────────────────────────────────────────────┐│   │
│  │  │  Discovers: environments/*/values.yaml                  ││   │
│  │  │                                                          ││   │
│  │  │  Generated Applications:                                ││   │
│  │  │  ┌──────────┬──────────┬──────────┬──────────────────┐ ││   │
│  │  │  │ Dev      │ QA       │ feat-123 │ [any-env-name]   │ ││   │
│  │  │  └──────────┴──────────┴──────────┴──────────────────┘ ││   │
│  │  └─────────────────────────────────────────────────────────┘│   │
│  └─────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────┬────────────────────────────────┘
                                     │ Deploy & Manage
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                               │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  PostgresVDB Operator                                        │  │
│  │  (Watches PostgresVDB CRDs)                                  │  │
│  └──────────────────┬───────────────────────────────────────────┘  │
│                     │ Provisions & Manages                          │
│                     ▼                                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Namespace: postgres-vdbs-dev                               │   │
│  │  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐  │   │
│  │  │ PostgresVDB CR │  │  PostgreSQL    │  │   Service    │  │   │
│  │  │   (dev-vdb)    │  │     Pod        │  │  (ClusterIP) │  │   │
│  │  └────────────────┘  └────────────────┘  └──────────────┘  │   │
│  │  ┌────────────────┐  ┌────────────────┐                     │   │
│  │  │    Secret      │  │  Init Hooks    │                     │   │
│  │  │ (Credentials)  │  │    (Jobs)      │                     │   │
│  │  └────────────────┘  └────────────────┘                     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Namespace: postgres-vdbs-qa                                │   │
│  │  (Similar structure to dev)                                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Namespace: postgres-vdbs-feat-123                          │   │
│  │  (Dynamic feature branch environment)                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 │ Provision VDB
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  Delphix Data Control Tower                          │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Source Database: 10.0.1.54:largedb                          │  │
│  │  (Provides data snapshots for VDB provisioning)              │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Component Interactions

### 1. GitOps Workflow

```
Developer          Git Repo          ArgoCD           Kubernetes
    │                 │                 │                  │
    │──Create/Update──▶│                 │                  │
    │   values file   │                 │                  │
    │                 │                 │                  │
    │     Commit      │                 │                  │
    │    & Push       │                 │                  │
    │                 │                 │                  │
    │                 │◀────Poll────────│                  │
    │                 │   (every 3min)  │                  │
    │                 │                 │                  │
    │                 │─────Detect──────▶│                  │
    │                 │    Change        │                  │
    │                 │                 │                  │
    │                 │                 │──Create/Update───▶│
    │                 │                 │   Resources      │
    │                 │                 │                  │
    │                 │                 │◀────Status───────│
    │                 │                 │   Updates        │
    │                 │                 │                  │
    │◀────Notify──────│◀────Status──────│                  │
    │   (optional)    │                 │                  │
```

### 2. VDB Provisioning Flow

```
PostgresVDB CR           Operator              Delphix DCT        Kubernetes
     Created                  │                      │                │
       │                      │                      │                │
       │────Detected──────────▶│                      │                │
       │                      │                      │                │
       │                      │───Request VDB────────▶│                │
       │                      │   Provisioning       │                │
       │                      │                      │                │
       │                      │◀────VDB Data─────────│                │
       │                      │   (Snapshot)         │                │
       │                      │                      │                │
       │                      │──Create Pod──────────┼───────────────▶│
       │                      │  + PVC + Service     │                │
       │                      │                      │                │
       │                      │                      │                │
       │                      │◀───Pod Ready─────────┼────────────────│
       │                      │                      │                │
       │                      │──Execute Hooks───────┼───────────────▶│
       │                      │  (post-create)       │   (Jobs)       │
       │                      │                      │                │
       │                      │◀──Hooks Complete─────┼────────────────│
       │                      │                      │                │
       │◀──Update Status──────│                      │                │
       │  Phase: Running      │                      │                │
```

### 3. Environment Creation Lifecycle (Two Paths)

#### Path A: Self-Service via Backstage

```
Developer     Backstage         GitHub PR       ArgoCD         Kubernetes
    │            │                  │              │                │
    │──Access────▶│                  │              │                │
    │  /create   │                  │              │                │
    │            │                  │              │                │
    │──Fill Form─│                  │              │                │
    │  (VDB cfg) │                  │              │                │
    │            │                  │              │                │
    │            │──Generate PR─────▶│              │                │
    │            │  environments/   │              │                │
    │            │  {name}/         │              │                │
    │            │  values.yaml     │              │                │
    │            │                  │              │                │
    │◀──Review PR────────────────────│              │                │
    │            │                  │              │                │
    │──Merge PR──────────────────────▶│              │                │
    │            │                  │              │                │
    │            │                  │◀──Detect─────│                │
    │            │                  │  New Dir     │                │
    │            │                  │              │                │
    │            │                  │              │──Create────────▶│
    │            │                  │              │  VDB App       │
    │            │                  │              │  + Namespace   │
    │            │                  │              │                │
    │◀──Notify (Optional)────────────│              │                │
    │  VDB Ready │                  │              │                │
```

#### Path B: Direct via Makefile/Git

```
Developer     Makefile          Git Repo        ArgoCD         Kubernetes
    │            │                  │              │                │
    │──Execute───▶│                  │              │                │
    │  make      │                  │              │                │
    │  create-env│                  │              │                │
    │  ENV=name  │                  │              │                │
    │            │                  │              │                │
    │            │──Create Dir──────▶│              │                │
    │            │  environments/   │              │                │
    │            │  {name}/         │              │                │
    │            │  values.yaml     │              │                │
    │            │                  │              │                │
    │──Review & ─┤                  │              │                │
    │  Commit    │                  │              │                │
    │            │                  │              │                │
    │──Push──────┼──────────────────▶│              │                │
    │            │                  │              │                │
    │            │                  │◀──Detect─────│                │
    │            │                  │  New Dir     │                │
    │            │                  │              │                │
    │            │                  │              │──Create────────▶│
    │            │                  │              │  VDB App       │
    │            │                  │              │                │
    │◀──Monitor──│                  │              │                │
    │  argocd    │                  │              │                │
    │  app get   │                  │              │                │
```

### 4. Environment Deletion Lifecycle

```
Developer     Makefile/ArgoCD   Git Repo        Kubernetes
    │            │                  │                │
    │──Execute───▶│                  │                │
    │  make      │                  │                │
    │  delete-env│                  │                │
    │  ENV=name  │                  │                │
    │            │                  │                │
    │  [5 sec    │                  │                │
    │   warning] │                  │                │
    │            │                  │                │
    │            │──Delete App──────┼───────────────▶│
    │            │  --cascade       │   Delete VDB   │
    │            │                  │   Delete NS    │
    │            │                  │                │
    │            │  [Wait 10s]      │                │
    │            │                  │                │
    │            │──Force Delete────┼───────────────▶│
    │            │  (if needed)     │   Finalizers   │
    │            │                  │                │
    │            │──Remove Dir──────▶│                │
    │            │  environments/   │                │
    │            │  {name}/         │                │
    │            │                  │                │
    │──Commit &──┤                  │                │
    │  Push      │                  │                │
    │            │                  │                │
    │◀──Verify───│                  │                │
    │  Cleanup   │                  │                │
```

## Directory Structure Details

```
postgresvdb-environments/
│
├── README.md                       # Project overview and complete documentation
├── QUICKSTART.md                   # Quick reference guide
├── Makefile                        # Automation commands
├── .gitignore                      # Git ignore patterns
│
├── charts/                         # Helm charts
│   └── postgres-vdb/              # Main VDB chart
│       ├── Chart.yaml             # Chart metadata
│       ├── values.yaml            # Default values
│       ├── .helmignore            # Helm ignore patterns
│       └── templates/             # Kubernetes templates
│           ├── postgresvdb.yaml   # PostgresVDB CR template
│           ├── hooks.yaml         # Lifecycle hooks (Jobs)
│           ├── secrets.yaml       # Secrets and Service
│           └── _helpers.tpl       # Template helpers
│
├── environments/                   # Environment-specific values (directory-based)
│   ├── dev/                       # Development environment
│   │   └── values.yaml
│   ├── qa/                        # QA environment
│   │   └── values.yaml
│   ├── feat-123/                  # Feature branch 123
│   │   └── values.yaml
│   └── [env-name]/                # Additional environments
│       └── values.yaml            # Environment configuration
│
├── applications/                   # ArgoCD applications
│   ├── postgres-vdb-appset.yaml   # ApplicationSet (Git directory generator)
│   └── [legacy files]             # Old app-of-apps/applicationset files
│
├── backstage-templates/           # Backstage Software Templates
│   ├── template.yaml              # Self-service VDB creation template
│   ├── skeleton/                  # Template files
│   │   └── values.yaml            # Jinja2 template for environments
│   └── README.md                  # Template documentation
│
├── crds/                          # Custom Resource Definitions
│   └── postgresvdb.yaml           # PostgresVDB CRD
│
├── catalog-info.yaml              # Backstage catalog entities
├── template-location.yaml         # Backstage template location
│
└── [documentation files]          # README, QUICKSTART, ARCHITECTURE, etc.
```

## Data Flow

```
┌────────────────────────────────────────────────────────────────┐
│                     Source Database (DCT)                       │
│                    10.0.1.54:largedb                           │
└────────────────────────────────┬───────────────────────────────┘
                                 │
                                 │ Snapshot/VDB Data
                                 ▼
┌────────────────────────────────────────────────────────────────┐
│                   PostgresVDB Operator                          │
│  • Watches PostgresVDB CRs                                     │
│  • Provisions VDBs from Delphix                                │
│  • Manages lifecycle (create, refresh, delete)                 │
└────────────────────────────────┬───────────────────────────────┘
                                 │
                                 │ Creates & Manages
                                 ▼
┌────────────────────────────────────────────────────────────────┐
│               PostgreSQL VDB Instances                          │
│  ┌──────────────┬──────────────┬──────────────────────────┐   │
│  │ Persistent   │  PostgreSQL  │    Application           │   │
│  │  Volume      │   Container  │    Connection            │   │
│  │  (Data)      │  (Postgres   │   (Service)              │   │
│  │              │   16.9)      │                          │   │
│  └──────────────┴──────────────┴──────────────────────────┘   │
│                                                                 │
│  Lifecycle Hooks:                                              │
│  • post-create: Initialize schemas, create tables, set perms   │
│  • pre-delete: Cleanup tasks (optional)                        │
│  • post-refresh: Refresh cached data (optional)                │
└────────────────────────────────────────────────────────────────┘
                                 │
                                 │ Database Access
                                 ▼
┌────────────────────────────────────────────────────────────────┐
│                    Application Services                         │
│  • Development Teams                                           │
│  • Testing Frameworks                                          │
│  • CI/CD Pipelines                                             │
│  • Feature Branch Deployments                                  │
└────────────────────────────────────────────────────────────────┘
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Security Layers                             │
│                                                                  │
│  1. Git Repository Access                                       │
│     • SSH Keys / Personal Access Tokens                         │
│     • Branch protection rules                                   │
│     • Code review requirements                                  │
│                                                                  │
│  2. Kubernetes RBAC                                             │
│     • Namespace isolation                                       │
│     • ServiceAccount permissions                                │
│     • Role/RoleBinding for operator                             │
│                                                                  │
│  3. Secrets Management                                          │
│     • Kubernetes Secrets for DB credentials                     │
│     • Secret rotation (recommended)                             │
│     • External secret management (optional: Vault, etc.)        │
│                                                                  │
│  4. Network Policies (recommended)                              │
│     • Restrict pod-to-pod communication                         │
│     • Limit external access                                     │
│     • Egress controls                                           │
│                                                                  │
│  5. Database Security                                           │
│     • Strong passwords                                          │
│     • User permissions (least privilege)                        │
│     • Connection encryption (TLS/SSL)                           │
│     • Audit logging                                             │
│                                                                  │
│  6. ArgoCD Security                                             │
│     • SSO integration (optional)                                │
│     • AppProject restrictions                                   │
│     • Resource allow/deny lists                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Scalability Considerations

### Horizontal Scaling
- Multiple VDB instances per environment
- Feature branches scale independently
- ArgoCD can manage 100+ applications

### Resource Management
- Resource quotas per namespace
- Limit ranges for pods
- PVC storage class selection
- Node affinity/anti-affinity rules

### Performance Optimization
- PostgreSQL tuning per environment
- Connection pooling (PgBouncer)
- Read replicas for high-read workloads
- Caching strategies

## Monitoring Stack (Optional Integration)

```
┌────────────────────────────────────────────────────────────────┐
│                     Monitoring Architecture                     │
│                                                                 │
│  PostgreSQL VDB                                                │
│       │                                                         │
│       │ metrics                                                 │
│       ▼                                                         │
│  postgres_exporter                                             │
│       │                                                         │
│       │ scrape                                                  │
│       ▼                                                         │
│  Prometheus                                                     │
│       │                                                         │
│       │ query                                                   │
│       ▼                                                         │
│  Grafana Dashboards                                            │
│   • Connection metrics                                         │
│   • Query performance                                          │
│   • Resource usage                                             │
│   • VDB lifecycle events                                       │
│                                                                 │
│  AlertManager                                                   │
│   • VDB provisioning failures                                  │
│   • Resource threshold alerts                                  │
│   • Connection pool exhaustion                                 │
│   • Slow query alerts                                          │
└────────────────────────────────────────────────────────────────┘
```
