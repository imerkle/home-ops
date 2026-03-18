---
name: k8s-namespace-rules
description: Kubernetes namespace specification rules for home-ops repository
version: 1.0.0
---

# Kubernetes Namespace Specification Rules

## Rule: No Namespace in Metadata (Except Kustomization)

In this repository, Kubernetes resources should NOT specify a namespace in the metadata section, with the exception of Kustomization resources.

### Correct Pattern
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: my-app
spec:
  # ... specification
```

### Exception: Kustomization Resources
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system  # This is the only allowed namespace specification
spec:
  # ... specification
```

### Incorrect Pattern
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  namespace: my-namespace  # DON'T DO THIS
spec:
  # ... specification
```

## Rationale

- Namespaces are managed through directory structure and FluxCD Kustomization resources
- This approach maintains cleaner, more portable manifests
- Namespace assignment happens at the GitOps level through FluxCD
- Reduces redundancy and potential conflicts in namespace management

## Affected Resource Types

This rule applies to all Kubernetes resources EXCEPT:
- `Kustomization` (apiVersion: kustomize.toolkit.fluxcd.io/v1)
- `HelmRepository`, `OCIRepository`, `GitRepository` (these may need namespace for controller scoping)

## Enforcement

When creating or updating Kubernetes manifests in this repository:
1. Remove any namespace specifications from metadata sections
2. Ensure Kustomization resources retain their namespace (typically flux-system)
3. Let FluxCD handle namespace placement through its reconciliation process