# How to Register the Software Template

**Important**: Software Templates cannot be imported via the Backstage catalog-import UI. They must be registered in Backstage's configuration file.

## Method 1: Update Backstage Configuration (Recommended)

Edit your Backstage `app-config.yaml` or create a `app-config.local.yaml`:

```yaml
catalog:
  locations:
    # Add this location for the template
    - type: url
      target: https://github.com/DCSTOLF/postgresvdb-environments/blob/main/backstage-templates/template.yaml
      rules:
        - allow: [Template]
```

Then restart Backstage:

```bash
kubectl rollout restart deployment/backstage -n backstage
```

## Method 2: Create a Location Entity

If you can't modify the Backstage configuration, create a Location entity:

1. Create a new file `templates-location.yaml` at the repository root:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Location
metadata:
  name: postgres-vdb-templates
  description: Software templates for PostgreSQL VDB environments
spec:
  type: url
  targets:
    - https://github.com/DCSTOLF/postgresvdb-environments/blob/main/backstage-templates/template.yaml
```

2. Import this Location via catalog-import:
   - URL: `https://github.com/DCSTOLF/postgresvdb-environments/blob/main/templates-location.yaml`

## Method 3: Use Backstage CLI (Development)

If running Backstage locally:

```bash
backstage-cli catalog location add \
  https://github.com/DCSTOLF/postgresvdb-environments/blob/main/backstage-templates/template.yaml
```

## Verification

After registration, verify the template appears:

1. Go to: https://backstage.k8s.delphixdemo.com/create
2. Look for "Create PostgreSQL VDB Environment" template
3. The template should have the postgres/database/gitops tags

## Why Templates Can't Use catalog-import

The catalog-import UI is designed for:
- Components (applications, services)
- Resources (databases, queues, topics)
- Systems, Domains, Groups, Users
- APIs

Software Templates are scaffolding tools, not catalog entities, so they need to be registered via configuration or Location entities.
