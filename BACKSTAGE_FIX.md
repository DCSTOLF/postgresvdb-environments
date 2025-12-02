# Backstage Integration - Fixed! ✅

## What Was Wrong

### Issue 1: catalog-info.yaml Failed with "No component with that kind, name or namespace"

**Root Cause**: The `owner` field referenced `platform-team` which doesn't exist in your Backstage instance.

**Fix**: Changed all owner references to `user:default/dcstolf` (your actual Backstage user).

**Also Fixed**: Changed `dependsOn` references from `component:postgres-vdb-platform` to `component:default/postgres-vdb-platform` (must include namespace).

### Issue 2: template.yaml Failed Validation

**Root Cause**: Software Templates cannot be imported via the catalog-import UI. They must be registered differently.

**Fix**: Created three methods to register the template (see below).

## How to Fix Your Backstage Now

### Step 1: Re-import the Catalog (Fixed Version)

1. Go to: https://backstage.k8s.delphixdemo.com/catalog-import
2. Delete the old broken import if it's still there:
   - Go to Components and find `postgres-vdb-platform`
   - Click the ... menu → "Unregister Entity"
3. Import the **fixed** catalog:
   ```
   https://github.com/DCSTOLF/postgresvdb-environments/blob/main/catalog-info.yaml
   ```
4. ✅ Should now work without errors!

### Step 2: Register the Template (Choose ONE method)

#### Method A: Using Location Entity (Easiest)

1. Go to: https://backstage.k8s.delphixdemo.com/catalog-import
2. Import:
   ```
   https://github.com/DCSTOLF/postgresvdb-environments/blob/main/templates-location.yaml
   ```
3. This registers the template for you!

#### Method B: Update Backstage Config (Best for Production)

Add to your Backstage `app-config.yaml`:

```yaml
catalog:
  locations:
    - type: url
      target: https://github.com/DCSTOLF/postgresvdb-environments/blob/main/backstage-templates/template.yaml
      rules:
        - allow: [Template]
```

Restart Backstage:
```bash
kubectl rollout restart deployment/backstage -n backstage
```

## Verification

### Check Catalog Import Worked

1. Go to: https://backstage.k8s.delphixdemo.com/catalog
2. Search for "postgres-vdb"
3. You should see:
   - ✅ **postgres-vdb-platform** (Component)
   - ✅ **postgres-vdb-dev** (Resource)
   - ✅ **postgres-vdb-qa** (Resource)
   - ✅ **postgres-vdb-feat-123** (Resource)

### Check Template Registration Worked

1. Go to: https://backstage.k8s.delphixdemo.com/create
2. Look for: **"Create PostgreSQL VDB Environment"**
3. ✅ Should appear with postgres/database/gitops tags

## What Changed in the Files

### catalog-info.yaml
```diff
- owner: platform-team
+ owner: user:default/dcstolf

- dependsOn:
-   - component:postgres-vdb-platform
+ dependsOn:
+   - component:default/postgres-vdb-platform
```

### template.yaml
```diff
- owner: platform-team
+ owner: user:default/dcstolf
```

### New Files Created
- **templates-location.yaml** - Makes template registration easier
- **TEMPLATE_REGISTRATION.md** - Explains why templates need special registration
- **BACKSTAGE_QUICKSTART.md** - Quick start guide

## Why This Happened

1. **Owner Reference**: Backstage requires `spec.owner` to reference an actual User or Group entity in the catalog. `platform-team` didn't exist, but `user:default/dcstolf` does (you!).

2. **Namespace in References**: Entity references should include the namespace. While Backstage sometimes defaults to `default`, being explicit prevents issues.

3. **Template Registration**: Software Templates are scaffolding tools, not catalog entities. They're registered via configuration or Location entities, not the catalog-import UI (which is for Components/Resources/APIs).

## Next Steps

Once both imports succeed:

1. ✅ View your environments in Catalog: https://backstage.k8s.delphixdemo.com/catalog
2. ✅ Create new environments: https://backstage.k8s.delphixdemo.com/create
3. ✅ Watch ArgoCD auto-deploy them: https://argocd.k8s.delphixdemo.com/

You're all set! 🚀
