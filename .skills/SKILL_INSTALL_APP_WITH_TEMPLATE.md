---
name: app-template-installation
description: How to deploy a new application using the bjw-s app-template Helm chart in this GitOps repository
version: 2.0.0
---

# Deploying an Application with app-template

## Overview

This repository uses **FluxCD** + **Kustomize** + the [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts) Helm chart to deploy containerised applications. Every app follows the same layered structure so that FluxCD can reconcile it automatically.

## Directory Layout

```
kubernetes/apps/<namespace>/<app-name>/
├── ks.yaml                        # FluxCD Kustomization (entry point)
└── app/
    ├── helmrelease.yaml           # HelmRelease using app-template
    ├── kustomization.yaml         # Kustomize overlay (resources + generators)
    └── volsync.values.yaml        # (optional) VolSync backup sizes
```

Additional files you may add inside `app/`:

| File | Purpose |
|------|---------|
| `netpol.yaml` | NetworkPolicy for the app |
| `config.yaml` / `config.json` | App config mounted via ConfigMap |
| `probe.yaml` | Custom health-check probes |
| `httproute.yaml` / `tcproute.yaml` | Standalone Gateway API routes |
| `servicemonitor.yaml` | Prometheus scrape config |
| `secret.yaml` / `*.sops.yaml` | Secrets (plain or SOPS-encrypted) |
| `rbac.yaml` | RBAC roles/bindings |

---

## Step-by-step

### 1. Create the directory

```bash
mkdir -p kubernetes/apps/<namespace>/<app-name>/app
```

### 2. Create `ks.yaml` – FluxCD Kustomization

This is the entry point FluxCD reads. Two variants exist:

#### Minimal (no persistent storage)

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
spec:
  interval: 1h
  path: ./kubernetes/apps/<namespace>/<app-name>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  targetNamespace: <namespace>
  wait: false
```

#### With VolSync persistent storage (most apps that store data)

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
spec:
  dependsOn: []
  components:
    - ../../../../components/volsync
  targetNamespace: <namespace>
  interval: 1h
  path: ./kubernetes/apps/<namespace>/<app-name>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: false
  postBuild:
    substitute:
      APP: *app
```

**Key details:**

| Field | Why it matters |
|-------|---------------|
| `components: [../../../../components/volsync]` | Injects a VolSync HelmRelease that creates PVCs and backup schedules |
| `postBuild.substitute.APP: *app` | The VolSync component templates use `${APP}` everywhere — this substitution is **required** for VolSync to work |
| `dependsOn` | Use when the app needs another Kustomization to be healthy first (e.g. a database) |

Optional `postBuild` extras seen in the repo:
- `VOLSYNC_CAPACITY: 10Gi` — override default PVC size (default is `5Gi`)
- `substituteFrom` — pull variables from Secrets/ConfigMaps at reconciliation time

### 3. Create `app/kustomization.yaml`

#### Without VolSync

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
```

#### With VolSync

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
generatorOptions:
  disableNameSuffixHash: true
configMapGenerator:
  - name: ${APP}-volsync-values
    files:
      - values.yaml=volsync.values.yaml
resources:
  - ./helmrelease.yaml
```

The `configMapGenerator` creates a ConfigMap named `<app>-volsync-values` that the VolSync component's HelmRelease reads via `valuesFrom`. The `${APP}` variable is substituted by `postBuild` in step 2.

Add any extra resources to the `resources` list: `netpol.yaml`, `probe.yaml`, etc.

### 4. Create `app/volsync.values.yaml` (if using VolSync)

```yaml
volumes:
  - name: <app-name>
    capacity: <size>Gi
```

For multiple PVCs (e.g. data + cache):

```yaml
volumes:
  - name: <app-name>
    capacity: 5Gi
  - name: <app-name>-cache
    capacity: 1Gi
```

Each entry creates a PVC named exactly by `name` with the given `capacity`. These PVCs are then referenced in the HelmRelease persistence section.

### 5. Create `app/helmrelease.yaml`

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app-name>
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: app-template
  values:
    controllers:
      <app-name>:
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: <image>
              tag: <tag>
            env:
              PORT: &port "<port>"
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: false
              capabilities: { drop: ["ALL"] }
            resources:
              requests:
                cpu: 10m
                memory: 100Mi
              limits:
                memory: 500Mi
    service:
      app:
        controller: <app-name>
        ports:
          http:
            port: *port
    route:
      app:
        enabled: true
        parentRefs:
          - name: envoy-internal
            namespace: network
        hostnames:
          - "{{ .Release.Name }}.${DOMAIN1}"
        rules:
          - backendRefs:
              - port: *port
                name: <app-name>
    persistence:
      data:
        existingClaim: "{{ .Release.Name }}"
        globalMounts:
          - path: /data
```

### 6. Register the app in the namespace kustomization

Edit `kubernetes/apps/<namespace>/kustomization.yaml` and add a line:

```yaml
resources:
  - ./namespace.yaml
  # ... existing apps ...
  - ./<app-name>/ks.yaml        # ← add this
```

---

## Reference: Common HelmRelease Patterns

### Persistence types

| Pattern | When to use | Example |
|---------|-------------|---------|
| `existingClaim: "{{ .Release.Name }}"` | VolSync-managed PVC | Forgejo data, Zot registry |
| `existingClaim: ${APP}` | VolSync with postBuild substitution | Zot registry variant |
| `type: emptyDir` | Ephemeral scratch space | ChatMock `/app`, litellm cache |
| `type: configMap` | Mount config files | Litellm config, Zot config |

### Multiple persistence volumes

```yaml
persistence:
  config:
    existingClaim: "{{ .Release.Name }}"
    globalMounts:
      - path: /config
  cache:
    existingClaim: "{{ .Release.Name }}-cache"
    globalMounts:
      - path: /config/.venv
  tmp:
    type: emptyDir
```

### Init containers (database init, git clone, etc.)

```yaml
controllers:
  <app-name>:
    initContainers:
      init-db:
        image:
          repository: ghcr.io/onedr0p/postgres-init
          tag: "16.4"
        env:
          INIT_POSTGRES_DBNAME: "<db-name>"
          INIT_POSTGRES_HOST: "vault:secret/data/pg_default#HOST"
          INIT_POSTGRES_USER: "vault:secret/data/pg_default#USER"
          INIT_POSTGRES_PASS: "vault:secret/data/pg_default#PASSWORD"
          INIT_POSTGRES_SUPER_PASS: "vault:secret/data/pg_default#PASSWORD"
```

### Pod security context

```yaml
controllers:
  <app-name>:
    pod:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: "OnRootMismatch"
```

### Health probes

```yaml
probes:
  liveness: &probe
    enabled: true
    custom: true
    spec:
      httpGet:
        path: /health
        port: *port
      initialDelaySeconds: 5
  readiness: *probe
```

### Route annotations (homepage integration)

```yaml
route:
  app:
    annotations:
      gethomepage.dev/enabled: "true"
      gethomepage.dev/name: My App
      gethomepage.dev/description: Description
      gethomepage.dev/group: Development
      gethomepage.dev/icon: app.png
```

### Vault secrets

Environment variables prefixed with `vault:` are injected by the Vault webhook:

```yaml
env:
  SECRET_KEY: "vault:secret/data/<path>#<field>"
```

### Helm remediation (for flaky installs)

```yaml
spec:
  maxHistory: 2
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  uninstall:
    keepHistory: false
```

---

## How VolSync works under the hood

1. The **VolSync component** (`kubernetes/components/volsync/`) is a Kustomize Component that adds:
   - A `${APP}-volsync-defaults` ConfigMap with default volume config
   - A `${APP}-volsync` HelmRelease that provisions PVCs and ReplicationDestination/Source CRDs
   - A patch making the app's HelmRelease `dependsOn` the volsync HelmRelease

2. The component reads values from two ConfigMaps:
   - `${APP}-volsync-defaults` — created by the component itself (default 5Gi)
   - `${APP}-volsync-values` — created by **your** app's `kustomization.yaml` configMapGenerator

3. The `postBuild.substitute.APP` variable is what makes all the `${APP}` references resolve.

**Without `postBuild.substitute.APP`, VolSync will fail** because `${APP}` remains unresolved.

---

## Shared Components (namespace kustomization)

Each namespace-level `kustomization.yaml` includes shared components:

```yaml
components:
  - ../../components/alerts    # Alertmanager notifications
  - ../../components/repos     # OCIRepository for app-template
```

The `repos` component provides the `app-template` OCIRepository that all HelmReleases reference via `chartRef.kind: OCIRepository, name: app-template`.

---

## Checklist for new app deployment

- [ ] Create `<app>/ks.yaml` with correct `path`, `targetNamespace`
- [ ] If persistent: add `components: [../../../../components/volsync]` and `postBuild.substitute.APP`
- [ ] Create `app/kustomization.yaml` with resources and (if VolSync) `configMapGenerator`
- [ ] If persistent: create `app/volsync.values.yaml` with volume names matching `existingClaim` references
- [ ] Create `app/helmrelease.yaml` with image, ports, service, route, persistence
- [ ] Add `- ./<app>/ks.yaml` to namespace `kustomization.yaml`
- [ ] Commit and push — FluxCD reconciles automatically
