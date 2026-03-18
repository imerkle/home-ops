---
name: archive-app
description: How to archive (retire) an application from this GitOps repository while preserving its history in an archive folder
version: 1.0.0
---

# Archiving an Application

## Overview

When an application is no longer needed but you want to preserve its configuration for future reference, archive it instead of deleting it. The archive folder mirrors the original directory structure so files are easy to locate and restore later.

## Archive Directory Convention

```
archive/
└── <namespace>/          # mirrors kubernetes/apps/<namespace>/
    └── <app-name>/       # full app directory preserved as-is
        ├── ks.yaml
        └── app/
            ├── helmrelease.yaml
            ├── kustomization.yaml
            └── ...
```

The `archive/` directory lives at the **repository root**, and the path inside it mirrors the relative path under `kubernetes/apps/` — so `kubernetes/apps/dev-system/mcp/cliproxyapi` becomes `archive/dev-system/mcp/cliproxyapi`.

---

## Step-by-step

### 1. Identify the app path and its parent kustomization

```
APP_PATH=kubernetes/apps/<namespace>/<app-name>
PARENT_KS=kubernetes/apps/<namespace>/kustomization.yaml
# e.g. for a sub-group like mcp/:
APP_PATH=kubernetes/apps/dev-system/mcp/cliproxyapi
PARENT_KS=kubernetes/apps/dev-system/kustomization.yaml
```

### 2. Copy the app directory into archive, preserving structure

```bash
mkdir -p archive/<namespace>/<optional-subdir>
cp -r kubernetes/apps/<namespace>/<app-name> archive/<namespace>/<optional-subdir>/<app-name>
```

Example:
```bash
mkdir -p archive/dev-system/mcp
cp -r kubernetes/apps/dev-system/mcp/cliproxyapi archive/dev-system/mcp/cliproxyapi
```

Verify all files were copied:
```bash
find archive/<namespace>/<app-name> -type f
```

### 3. Remove the reference from the parent kustomization

Open the parent `kustomization.yaml` that lists the app's `ks.yaml` and remove the resource entry.

Before:
```yaml
resources:
  - ./mcp/context7/ks.yaml
  - ./mcp/cliproxyapi/ks.yaml   # <-- remove this line
  - ./headlamp/ks.yaml
```

After:
```yaml
resources:
  - ./mcp/context7/ks.yaml
  - ./headlamp/ks.yaml
```

### 4. Delete the original app directory

```bash
rm -rf kubernetes/apps/<namespace>/<app-name>
```

> **Note:** If the app was inside a shared sub-directory (e.g. `mcp/`) and that directory still contains other apps, do **not** delete the parent directory.

### 5. Commit

```bash
git add archive/<namespace>/<app-name> kubernetes/apps/<namespace>/kustomization.yaml
git rm -r kubernetes/apps/<namespace>/<app-name>
git commit -m "chore: archive <app-name> from <namespace>"
```

---

## Restoring an Archived App

To restore an archived app, reverse the process:

```bash
# 1. Copy back from archive
cp -r archive/<namespace>/<app-name> kubernetes/apps/<namespace>/<app-name>

# 2. Re-add the resource entry to the parent kustomization.yaml

# 3. (Optional) Remove from archive if desired
rm -rf archive/<namespace>/<app-name>

# 4. Commit
git add .
git commit -m "chore: restore <app-name> to <namespace>"
```

---

## Checklist

- [ ] Identify app path: `kubernetes/apps/<namespace>/[subdir/]<app-name>`
- [ ] Identify parent kustomization that references the app's `ks.yaml`
- [ ] `cp -r` app directory to `archive/<namespace>/[subdir/]<app-name>`
- [ ] Verify archive copy with `find archive/... -type f`
- [ ] Remove the `ks.yaml` resource line from parent `kustomization.yaml`
- [ ] Delete the original app directory
- [ ] Commit with message `chore: archive <app-name> from <namespace>`
