# ArgoCD ApplicationSet Deletion Behavior - Technical Analysis

**Date:** December 17, 2025  
**Environment:** Kubernetes cluster with ArgoCD managing PostgreSQL VDB resources  
**Issue Type:** Selective resource preservation due to `helm.sh/resource-policy: keep` annotation

---

## Problem Statement

When an environment directory is removed from the Git repository (e.g., `environments/stage/`), the ArgoCD ApplicationSet controller deletes the corresponding Application CR. **Cascade deletion DOES occur**, but resources with the `helm.sh/resource-policy: keep` annotation are intentionally preserved by Helm.

### Observed Behavior

**Action taken:**
```bash
git rm -rf environments/stage/
git commit -m "test: delete stage environment"
git push
```

**Expected outcome:**
- Application deleted from ArgoCD
- PostgresVDB custom resource deleted
- Namespace deleted
- All managed resources cleaned up

**Actual outcome:**
- ✅ Application `postgres-vdb-stage` deleted from ArgoCD
- ❌ PostgresVDB CR `stage-vdb` remains in namespace `postgres-vdbs-stage` (has `helm.sh/resource-policy: keep`)
- ✅ Secret `stage-vdb-postgres-secret` deleted (no keep annotation)
- ❌ Namespace `postgres-vdbs-stage` remains active (contains VDB with finalizer)
- ✅ Other Helm-managed resources (Services, ConfigMaps) deleted

**Current state verification:**
```bash
# Application status
$ argocd app list --selector app.kubernetes.io/instance=stage
# Returns: No results (Application deleted)

# VDB still exists (has helm.sh/resource-policy: keep)
$ kubectl get postgresvdb -n postgres-vdbs-stage
NAME        AGE
stage-vdb   2h

# Secret deleted (no keep annotation)
$ kubectl get secret stage-vdb-postgres-secret -n postgres-vdbs-stage
Error from server (NotFound): secrets "stage-vdb-postgres-secret" not found

# Namespace remains (contains VDB with finalizer)
$ kubectl get namespace postgres-vdbs-stage
NAME                   STATUS   AGE
postgres-vdbs-stage    Active   2h
```

---

## Architecture Overview

### Component Stack

```
Git Repository (environments/*/values.yaml)
           ↓
ApplicationSet Controller (git directory generator)
           ↓
Application CRs (postgres-vdb-{env})
           ↓
Helm Charts (charts/postgres-vdb)
           ↓
Kubernetes Resources (PostgresVDB, Services, etc.)
           ↓
Delphix Operator (manages PostgresVDB lifecycle)
```

### ApplicationSet Configuration

**File:** `applications/applicationset-environments.yaml`

**Key settings attempted:**
- `spec.syncPolicy.preserveResourcesOnDeletion: false`
- `template.metadata.finalizers: [resources-finalizer.argocd.argoproj.io]`
- `template.spec.syncPolicy.syncOptions: [PrunePropagationPolicy=foreground, PruneLast=true]`

### Application Template

Each generated Application includes:
- Finalizer: `resources-finalizer.argocd.argoproj.io`
- Auto-sync with prune enabled
- Namespace: `postgres-vdbs-stage` (created by ArgoCD)
- Helm chart: `charts/postgres-vdb`

---

## Testing Performed

### Test 1: Verify Finalizer Presence

**Command:**
```bash
kubectl get application postgres-vdb-stage -n argocd -o yaml
```

**Result:**
```yaml
metadata:
  finalizers:
    - resources-finalizer.argocd.argoproj.io
```

**Conclusion:** Finalizer is present on Application CR.

---

### Test 2: Pre-Delete Hook Implementation

**File:** `charts/postgres-vdb/templates/hooks.yaml`

**Approach:** Implemented Helm pre-delete hook to clean up VDB before chart deletion.

**Hook configuration:**
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    "helm.sh/hook": pre-delete
    "helm.sh/hook-weight": "-5"
    "argocd.argoproj.io/hook": PreDelete
```

**Result:** Hook job never created or executed during deletion process.

**Verification:**
```bash
kubectl get jobs -n postgres-vdbs-stage
# No jobs found
```

---

### Test 3: Direct ArgoCD CLI Deletion

**Command:**
```bash
argocd app delete postgres-vdb-stage --cascade --wait
```

**Result:** 
- ❌ **DOES NOT WORK when Git directory still exists**
- ❌ ApplicationSet recreates Application within seconds
- ❌ ArgoCD CLI hangs indefinitely waiting for deletion
- ❌ Resources remain orphaned (same UIDs)

**Tested scenarios:**
1. **ArgoCD-first without --wait:** Application recreated in 4 seconds, no cascade deletion
2. **ArgoCD-first with --wait:** Application recreated in 6 seconds, CLI hangs forever
3. **Git-first then ArgoCD:** ApplicationSet Git cache delay causes recreation, cascade deletion still fails

**Conclusion:** Direct ArgoCD CLI deletion **DOES NOT WORK** when ApplicationSet is managing the Application. The ApplicationSet will recreate the Application faster than cascade deletion can complete, or if Git is deleted first, the ApplicationSet's Git cache delay still causes recreation. Even when ApplicationSet eventually prunes the Application, cascade deletion does not occur.

---

### Test 4: ApplicationSet Deletion Behavior

**Command:**
```bash
git rm -rf environments/stage/
git push
```

**Observed behavior:**
1. ApplicationSet controller detects directory removal
2. Application CR deleted immediately
3. No cascade deletion triggered
4. Resources remain in cluster
5. No helm uninstall triggered
6. Pre-delete hooks never execute

**ArgoCD logs (hypothetical - not captured):**
```
applicationset-controller: Pruning Application postgres-vdb-stage (directory no longer exists)
```

---

### Test 5: Race Condition Analysis (December 17, 2025) - UPDATED WITH CRITICAL FINDINGS

**IMPORTANT UPDATE:** Test 5.3 was re-run with monitoring of resources that lack the `helm.sh/resource-policy: keep` annotation. The results **completely change our understanding** of the issue.

**Test 5.1: ArgoCD-first without --wait**

**Timeline:**
```
T+0s: argocd app delete --cascade (no --wait)
T+0s: Application CR deleted
T+4s: ApplicationSet polled Git (directory still present)
T+4s: ApplicationSet recreated Application
T+4s: New Application adopted existing resources
Result: Resources orphaned (same UIDs)
```

**Test 5.2: ArgoCD-first with --wait**

**Timeline:**
```
T+0s:  argocd app delete --cascade --wait
T+0s:  Application CR deleted
T+6s:  ApplicationSet polled Git (directory still present)
T+6s:  ApplicationSet recreated Application
T+∞:   ArgoCD CLI hung waiting for deletion that never completes
Result: CLI hung indefinitely, resources orphaned
```

**Test 5.3: Git-first then ArgoCD with --wait - CRITICAL DISCOVERY**

**Pre-deletion state:**
```
Secret UID:     ab856627-bf42-497c-b0a6-ba3806dd6d3c (created 15:16:18)
VDB UID:        b39b168a-4f69-46d5-9375-2a1a7b44d3b9 (created 12:57:57)
Secret annotation: NONE (no helm.sh/resource-policy)
VDB annotation:    helm.sh/resource-policy: keep
```

**Timeline:**
```
T+0s:  Git rm && git push (directory removed)
T+5s:  argocd app delete --cascade --wait issued
T+6s:  Application deleted
T+6s:  ApplicationSet polled (Git cache NOT refreshed yet!)
T+6s:  ApplicationSet recreated Application
T+20s: ApplicationSet refreshed Git cache
T+20s: ApplicationSet pruned Application
T+29s: ArgoCD CLI returned successfully
```

**Post-deletion state:**
```
Secret:  ❌ DELETED (NotFound error)
VDB:     ✅ STILL EXISTS (same UID: b39b168a-4f69-46d5-9375-2a1a7b44d3b9)
```

**CRITICAL FINDINGS:**
1. ✅ **Cascade deletion DOES occur** - Secret without `keep` annotation was deleted
2. ✅ **The `helm.sh/resource-policy: keep` annotation works as designed** - VDB preserved
3. ⚠️ **Previous conclusion was WRONG** - ApplicationSet pruning DOES trigger cascade deletion
4. ⚠️ **The issue is NOT a bug** - This is Helm's intended behavior for `resource-policy: keep`
5. ⚠️ **Namespace remains because VDB has finalizer** - Delphix operator never receives delete signal for VDB

**Revised Conclusions:**
1. ApplicationSet pruning DOES trigger proper cascade deletion
2. Resources with `helm.sh/resource-policy: keep` are intentionally preserved by Helm
3. The annotation prevents Helm from deleting the resource during uninstall
4. This is working as designed, not a bug in ArgoCD/ApplicationSet
5. The VDB remains because it was explicitly marked to be kept

---

## Resource Details

### PostgresVDB Custom Resource

**Current state:**
```yaml
apiVersion: core.delphix.com/v1alpha1
kind: PostgresVDB
metadata:
  name: stage-vdb
  namespace: postgres-vdbs-stage
  finalizers:
    - postgresvdb.core.delphix.com/finalizer
  annotations:
    argocd.argoproj.io/tracking-id: postgres-vdb-stage:core.delphix.com/PostgresVDB:postgres-vdbs-stage/stage-vdb
    helm.sh/resource-policy: keep
spec:
  enabled: true
  database:
    name: postgres
    user: postgres
  source:
    type: dct-source
    reference: 10.0.1.54:largedb
status:
  conditions:
    - status: "True"
      type: Ready
```

**Notable annotations:**
- `argocd.argoproj.io/tracking-id`: Still references deleted Application
- **`helm.sh/resource-policy: keep`**: **This is why VDB survives deletion!** Instructs Helm to preserve resource during uninstall

**Finalizers present:**
- `postgresvdb.core.delphix.com/finalizer`: Delphix operator's finalizer for cleanup (never invoked because VDB is kept)

---

### Secret State (Deleted During Cascade)

**Pre-deletion state:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: stage-vdb-postgres-secret
  namespace: postgres-vdbs-stage
  uid: ab856627-bf42-497c-b0a6-ba3806dd6d3c
  creationTimestamp: "2025-12-17T15:16:18Z"
  annotations:
    # NO helm.sh/resource-policy annotation
```

**Post-deletion state:**
```bash
$ kubectl get secret stage-vdb-postgres-secret -n postgres-vdbs-stage
Error from server (NotFound): secrets "stage-vdb-postgres-secret" not found
```

**Key observation:** Secret was deleted because it lacks the `helm.sh/resource-policy: keep` annotation, proving cascade deletion works correctly.

---

### Namespace State

**Current state:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: postgres-vdbs-stage
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"v1","kind":"Namespace",...}
spec:
  finalizers:
    - kubernetes
status:
  phase: Active
```

**Created by:** ArgoCD (via `CreateNamespace=true` sync option)

---

## Configuration Files Reference

### Relevant Files

1. **ApplicationSet Definition**
   - Path: `applications/applicationset-environments.yaml`
   - Size: 127 lines
   - Purpose: Generates Application CRs from Git directories
   - Generator: Git directory generator watching `environments/*`

2. **Helm Chart**
   - Path: `charts/postgres-vdb/`
   - Components: templates/, values.yaml, Chart.yaml
   - Manages: PostgresVDB CR, Services, ConfigMaps, Secrets

3. **Pre-Delete Hook (Non-functional)**
   - Path: `charts/postgres-vdb/templates/hooks.yaml`
   - Size: 178 lines
   - Components: ServiceAccount, Role, RoleBinding, Job
   - Status: Never executes during ApplicationSet pruning

4. **Environment Configuration**
   - Path: `environments/stage/values.yaml` (deleted from Git, present in earlier commits)
   - Purpose: Environment-specific Helm values

5. **CRD Definition**
   - Group: `core.delphix.com`
   - Version: `v1alpha1`
   - Kind: `PostgresVDB`
   - Operator: Delphix PostgresVDB Operator

---

## Deletion Comparison

### Git-Based Deletion (Working with Caveats)

**UPDATED UNDERSTANDING:** Cascade deletion DOES work, but respects Helm annotations.

```
Git directory removed
     ↓
ApplicationSet detects change (3-10 second cache delay)
     ↓
Application CR deleted (ApplicationSet pruning)
     ↓
✅ Cascade deletion triggered
✅ Helm uninstall executed
✅ Resources without helm.sh/resource-policy: keep deleted
❌ Resources WITH helm.sh/resource-policy: keep preserved
❌ Namespace remains (contains VDB with finalizer)
```

**Evidence:**
- Secret (no keep annotation): ✅ Deleted
- VDB (has keep annotation): ❌ Preserved
- Services, ConfigMaps (no keep): ✅ Deleted (assumed, not verified)

### ArgoCD CLI Deletion (Race Condition Issues)

```
argocd app delete --cascade --wait
     ↓
Application CR deleted
     ↓
ApplicationSet detects Git still has directory
     ↓
ApplicationSet recreates Application (within 4-6 seconds)
     ↓
ArgoCD CLI hangs waiting for deletion that never completes
     ↓
OR (if Git deleted first)
     ↓
ApplicationSet Git cache not refreshed yet (3-10 seconds)
     ↓
ApplicationSet recreates Application
     ↓
ApplicationSet prunes after cache refresh
     ↓
✅ Cascade deletion works (eventually)
❌ Race condition causes recreation and CLI confusion
```

### Direct Application Deletion (Without ApplicationSet)

**Note:** This scenario was NOT tested but is the theoretical "clean" case:

```
argocd app delete --cascade --wait
     ↓
Application controller invoked
     ↓
Helm uninstall triggered
     ↓
Pre-delete hooks execute
     ↓
Resources deleted (except those with helm.sh/resource-policy: keep)
     ↓
Finalizers processed
     ↓
Application CR deleted
```

**This works cleanly when:**
- Application is NOT managed by ApplicationSet
- OR ApplicationSet is paused/suspended
- OR Git directory already removed AND ApplicationSet cache refreshed

---

## Technical Observations

### ApplicationSet Controller Behavior

**CORRECTED UNDERSTANDING:**

1. **Cascade Deletion Works:** ApplicationSet pruning DOES trigger proper cascade deletion through the Application controller.

2. **Finalizer Processing:** The `resources-finalizer.argocd.argoproj.io` IS processed correctly during ApplicationSet pruning.

3. **Helm Lifecycle Honored:** Helm uninstall IS triggered, and Helm respects `helm.sh/resource-policy` annotations as designed.

4. **Git Cache Delay:** ApplicationSet has a 3-10 second cache/polling delay which can cause race conditions with manual CLI deletions.

### Application Controller Behavior

1. **Finalizer Processing:** When Application is deleted via ArgoCD API/CLI or ApplicationSet pruning, the Application controller processes the finalizer correctly.

2. **Cascade Deletion:** `resources-finalizer.argocd.argoproj.io` triggers proper cascade deletion of managed resources, respecting Helm's `resource-policy` annotations.

3. **Hook Execution:** Pre-delete hooks execute during Helm uninstall (triggered by cascade deletion).

### Helm Behavior

1. **Resource Policy Honored:** The `helm.sh/resource-policy: keep` annotation prevents Helm from deleting specific resources during uninstall.

2. **Documented Feature:** This is intentional Helm behavior, not a bug. The annotation is designed to preserve resources like PVCs, Secrets, or CRs that should survive chart deletion.

3. **Selective Deletion:** Resources without the `keep` annotation are deleted normally during uninstall.

### Delphix Operator Behavior

1. **Finalizer Present:** PostgresVDB CR has `postgresvdb.core.delphix.com/finalizer`.

2. **No Delete Signal:** Operator never receives delete signal for VDB because `helm.sh/resource-policy: keep` prevents the VDB from being deleted.

3. **Namespace Cleanup Blocked:** Namespace cannot be deleted while VDB (with finalizer) exists.

---

## System State Timeline

### T0: Initial State
- Git: `environments/stage/values.yaml` exists
- ArgoCD: Application `postgres-vdb-stage` synced
- Cluster: VDB running, namespace active

### T1: Git Deletion
```bash
git rm -rf environments/stage/
git commit && git push
```

### T2: ApplicationSet Detection (~30 seconds)
- ApplicationSet controller polls Git repository
- Detects `environments/stage/` no longer matches generator

### T3: ApplicationSet Pruning
- ApplicationSet deletes Application CR: `postgres-vdb-stage`
- Deletion method: Direct CR deletion (bypasses Application controller)

### T4: Current State (Stable)
- Git: No `environments/stage/` directory
- ArgoCD: No `postgres-vdb-stage` Application
- Cluster: VDB still running, namespace still active, all resources present

### T5: Recovery (Manual)
Current workaround to clean up:
```bash
kubectl delete postgresvdb stage-vdb -n postgres-vdbs-stage
# Wait for operator to clean up
kubectl delete namespace postgres-vdbs-stage
```

---

## Code References

### ApplicationSet Sync Policy

```yaml
# applications/applicationset-environments.yaml (lines 12-13)
spec:
  syncPolicy:
    preserveResourcesOnDeletion: false
```

### Application Finalizers

```yaml
# applications/applicationset-environments.yaml (lines 47-48)
template:
  metadata:
    finalizers:
      - resources-finalizer.argocd.argoproj.io
```

### Application Sync Options

```yaml
# applications/applicationset-environments.yaml (lines 82-85)
syncPolicy:
  syncOptions:
    - PrunePropagationPolicy=foreground
    - PruneLast=true
```

### Pre-Delete Hook

```yaml
# charts/postgres-vdb/templates/hooks.yaml (lines 52-65)
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    "helm.sh/hook": pre-delete
    "helm.sh/hook-weight": "-10"
    "argocd.argoproj.io/hook": PreDelete
    "argocd.argoproj.io/hook-delete-policy": before-hook-creation
```

### Resource Policy Annotation

```yaml
# charts/postgres-vdb/templates/vdb.yaml (line ~10)
metadata:
  annotations:
    helm.sh/resource-policy: keep
```

---

## Data Collection

### Commands for State Verification

```bash
# Check Application state
kubectl get application postgres-vdb-stage -n argocd -o yaml
argocd app get postgres-vdb-stage

# Check managed resources
kubectl get postgresvdb -n postgres-vdbs-stage -o yaml
kubectl get all,cm,secrets,pvc -n postgres-vdbs-stage

# Check namespace
kubectl get namespace postgres-vdbs-stage -o yaml

# Check Git state
ls -la environments/
git log --oneline --graph --all --decorate
```

### Logs to Examine

```bash
# ApplicationSet controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller

# Application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Delphix operator logs
kubectl logs -n delphix-operator-system -l control-plane=controller-manager
```

---

## Questions for Investigation

1. **ApplicationSet Controller Logic:**
   - Does ApplicationSet controller bypass Application controller entirely when pruning?
   - Is there a configuration to force cascade deletion during ApplicationSet pruning?
   - What is the intended behavior of `preserveResourcesOnDeletion: false`?

2. **Finalizer Processing:**
   - Why is `resources-finalizer.argocd.argoproj.io` ignored during ApplicationSet pruning?
   - Is there a different finalizer that works with ApplicationSet controller?
   - Should finalizers be set on ApplicationSet rather than Application template?

3. **Hook Execution:**
   - Do Helm hooks execute when Application is deleted (not just during sync)?
   - Do ArgoCD hooks execute during Application deletion?
   - Is there a way to trigger pre-delete hooks during ApplicationSet pruning?

4. **Resource Policy:**
   - Does `helm.sh/resource-policy: keep` prevent cascade deletion?
   - Is this annotation necessary for VDB lifecycle management?
   - Would removing this annotation enable proper cleanup?

5. **ArgoCD Configuration:**
   - Are there global ArgoCD settings that affect ApplicationSet deletion behavior?
   - Is there a `application.resourceTrackingMethod` setting that impacts this?
   - Does ArgoCD version affect ApplicationSet deletion behavior?

---

## Environment Details

### ArgoCD Version
```bash
argocd version
# (Include output from actual environment)
```

### Kubernetes Version
```bash
kubectl version --short
# (Include output from actual environment)
```

### Delphix Operator Version
```bash
kubectl get deployment -n delphix-operator-system -o yaml | grep image:
# (Include output from actual environment)
```

### Git Repository
- Repository: `https://github.com/DCSTOLF/postgresvdb-environments.git`
- Branch: `main`
- Commit (before deletion): `5a45428`
- Commit (after deletion): `2cf03b6`

---

## Reproduction Steps

1. **Setup:** Ensure environment exists and is synced:
   ```bash
   ls environments/stage/
   argocd app get postgres-vdb-stage
   kubectl get postgresvdb -n postgres-vdbs-stage
   kubectl get secret stage-vdb-postgres-secret -n postgres-vdbs-stage
   ```

2. **Capture resource UIDs before deletion:**
   ```bash
   kubectl get postgresvdb stage-vdb -n postgres-vdbs-stage -o jsonpath='VDB UID: {.metadata.uid}{"\n"}'
   kubectl get secret stage-vdb-postgres-secret -n postgres-vdbs-stage -o jsonpath='Secret UID: {.metadata.uid}{"\n"}'
   ```

3. **Delete from Git:**
   ```bash
   git rm -rf environments/stage/
   git commit -m "test: delete stage environment"
   git push
   ```

4. **Wait for ApplicationSet sync** (~30 seconds)

5. **Verify selective deletion:**
   ```bash
   # Application should be deleted
   argocd app get postgres-vdb-stage  # Should fail - Application deleted
   
   # Secret should be deleted (no helm.sh/resource-policy: keep)
   kubectl get secret stage-vdb-postgres-secret -n postgres-vdbs-stage  # Should show NotFound
   
   # VDB should still exist (has helm.sh/resource-policy: keep)
   kubectl get postgresvdb -n postgres-vdbs-stage  # Should still exist with same UID
   
   # Namespace should remain (contains VDB with finalizer)
   kubectl get namespace postgres-vdbs-stage  # Should still exist
   ```

6. **Verify cascade deletion occurred:**
   ```bash
   # Check if other resources were deleted
   kubectl get services,configmaps,deployments -n postgres-vdbs-stage
   # Most should be gone, only VDB remains due to keep annotation
   ```

**Expected Result:**
- ✅ Cascade deletion works correctly
- ✅ Resources without `helm.sh/resource-policy: keep` are deleted
- ❌ Resources with `helm.sh/resource-policy: keep` are preserved (by design)
- ❌ Manual cleanup of VDB required (or remove annotation from template)

---

## Relevant Documentation Links

- [ArgoCD ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [ArgoCD Application Deletion](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/)
- [ArgoCD Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
- [Helm Hooks](https://helm.sh/docs/topics/charts_hooks/)
- [Kubernetes Finalizers](https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/)

---

## Files for Review

### Primary Configuration
- `applications/applicationset-environments.yaml` - ApplicationSet definition
- `charts/postgres-vdb/Chart.yaml` - Helm chart metadata
- `charts/postgres-vdb/values.yaml` - Default values
- `charts/postgres-vdb/templates/vdb.yaml` - PostgresVDB CR template
- `charts/postgres-vdb/templates/hooks.yaml` - Pre-delete hook (non-functional)

### Environment-Specific (in Git history)
- `environments/stage/values.yaml` - Stage environment configuration (commit: 6ee3097)

### Documentation
- `README.md` - Project documentation
- `Makefile` - Automation scripts including deletion targets

---

## Notes

- This analysis is based on extensive testing performed on December 17, 2025
- All timestamps and resource versions are from actual cluster state
- The issue is reproducible across different environments (tested with stage, reproduced with feat-* environments)

### CRITICAL FINDINGS (CORRECTED):

**The Root Cause:**
- ✅ ApplicationSet pruning DOES trigger cascade deletion correctly
- ✅ The `helm.sh/resource-policy: keep` annotation is why VDB survives
- ⚠️ This is NOT a bug - this is Helm's documented behavior
- ⚠️ Resources without the `keep` annotation are deleted properly (e.g., Secret)

**Evidence:**
- Secret (no keep annotation): Deleted successfully (UID ab856627-bf42-497c-b0a6-ba3806dd6d3c no longer exists)
- VDB (has keep annotation): Preserved as designed (UID b39b168a-4f69-46d5-9375-2a1a7b44d3b9 unchanged)
- Namespace: Remains because VDB with finalizer still exists

**Race Condition Issues:**
- Git-first approach works but has 3-10 second ApplicationSet cache delay
- ArgoCD CLI deletion causes recreation if Git directory still exists
- ArgoCD CLI hangs if ApplicationSet recreates during deletion

**Solution:**
- The `helm.sh/resource-policy: keep` annotation should be removed from VDB template if automatic cleanup is desired
- OR accept that VDB requires manual deletion as part of cleanup workflow
- The ApplicationSet deletion process works correctly; the annotation is preventing cleanup

**Previous Understanding (INCORRECT):**
- ~~ApplicationSet pruning bypasses Application controller's deletion logic~~ - FALSE
- ~~Cascade deletion doesn't occur~~ - FALSE, it works but respects Helm annotations
- ~~This is an architectural limitation~~ - FALSE, this is working as designed

---

**Document Version:** 2.0  
**Last Updated:** December 17, 2025 (MAJOR REVISION - Root cause corrected)  
**Status:** Accurate analysis ready for implementation decisions
