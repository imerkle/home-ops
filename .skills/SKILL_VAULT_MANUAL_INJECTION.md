# Skill: Vault Secrets Injection (Automatic vs. Manual)

## Overview

In this cluster, HashiCorp Vault secrets interpolation and dynamic database lease renewals are handled by the Banzai Cloud `vault-secrets-webhook` (`bank-vaults`).

By default, **automatic webhook mutation** should be used. However, under specific operational conditions (notably CPU exhaustion and entrypoint wrapping issues), **manual injection** is required.

---

## 1. Automatic Webhook Mutation (Default Standard)

When a pod contains environment variables with `vault:...` references, or has the daemon annotation enabled, the webhook mutates the pod specification before admission.

### Standard Configuration

In BJW-S `app-template` (v3 / v4) `HelmRelease`:

```yaml
controllers:
  my-app:
    pod:
      annotations:
        # Enable daemon mode if using dynamic database credentials or secret renewal
        vault.security.banzaicloud.io/vault-env-daemon: "true"
    containers:
      app:
        image:
          repository: zot.${DOMAIN1}/my-app
          tag: v1.0.0
        env:
          DATABASE_URL: "postgres://$${vault:database/creds/my-role#username}:$${vault:database/creds/my-role#password}@pg-default-rw.db.svc.cluster.local:5432/mydb?sslmode=disable"
```

### What the Webhook Does Automatically:
1. Injects the `copy-vault-env` initContainer (`ghcr.io/bank-vaults/vault-env:v1.21.3`).
2. Creates an `emptyDir` memory volume mounted at `/vault/`.
3. Prepends `/vault/vault-env` to the container command/entrypoint.
4. Injects default Vault connection variables:
   - `VAULT_ADDR: "http://vault.vault.svc.cluster.local:8200"`
   - `VAULT_AUTH_METHOD: "jwt"`
   - `VAULT_PATH: "kubernetes"`
   - `VAULT_ROLE: "default"`
   - `VAULT_ENV_DAEMON: "true"` (when annotation is present)

---

## 2. Why & When to Use Manual Injection

Manual injection bypasses the mutating webhook by adding `vault.security.banzaicloud.io/mutate: "skip"`.

### Trigger Conditions for Manual Injection

### A. Node CPU Headroom < 50m (Scheduling Deadlock)
- **The Issue**: The bank-vaults webhook hardcodes resource requests on the injected `copy-vault-env` initContainer:
  ```yaml
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
  ```
- **The Symptom**: When a node is heavily allocated and has less than 50m of allocatable CPU left (e.g. 15m allocatable), Kubernetes rejects the pod with:
  `0/2 nodes available: 1 Insufficient cpu`.
- **The Solution**: With manual injection, you control the initContainer's resources and can set `requests.cpu: 0m` or `requests.cpu: 5m`, allowing the pod to schedule and run smoothly even under tight node limits.

### B. Complex Entrypoint Scripts & Multi-Process Containers
- **The Issue**: When images use custom wrapper entrypoints (e.g. `/app/entrypoint.sh` that starts Nginx and a backend Go process), the webhook's heuristic parsing of image `ENTRYPOINT` vs `CMD` can sometimes misorder arguments or fail if private registry metadata cannot be queried during admission.
- **The Solution**: Explicitly declaring `command: ["/vault/vault-env", "/app/entrypoint.sh"]` guarantees that `vault-env` executes first, populates the decrypted environment, and directly executes the shell script with proper signal handling.

### C. Custom Signal Forwarding & Termination Delays
- Manual injection lets you explicitly configure `VAULT_ENV_SIG: "SIGTERM"` and `VAULT_ENV_DELAY: "2"` to ensure parent processes receive clean shutdown signals before the vault daemon terminates.

---

## 3. How to Implement Manual Injection (Step-by-Step)

To switch an application to manual injection, apply the following 5 changes to its `HelmRelease`:

### Step 1: Add `mutate: "skip"` Annotation
```yaml
pod:
  annotations:
    vault.security.banzaicloud.io/mutate: "skip"
    vault.security.banzaicloud.io/vault-env-daemon: "true"
```

### Step 2: Add `copy-vault-env` InitContainer with Custom Resources
```yaml
initContainers:
  copy-vault-env:
    image:
      repository: ghcr.io/bank-vaults/vault-env
      tag: v1.21.3
    command: ["sh", "-c", "cp /usr/local/bin/vault-env /vault/"]
    resources:
      requests:
        cpu: 0m
        memory: 16Mi
      limits:
        cpu: 50m
        memory: 64Mi
    securityContext:
      runAsUser: 65534
      runAsGroup: 65534
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      seccompProfile:
        type: RuntimeDefault
```

### Step 3: Prefix Target Command with `/vault/vault-env`
```yaml
containers:
  app:
    image:
      repository: zot.${DOMAIN1}/my-app
      tag: v1.0.0
    command: ["/vault/vault-env", "/app/my-app"]
```

### Step 4: Add Vault Environment Variables
```yaml
    env:
      DATABASE_URL: "postgres://$${vault:database/creds/my-role#username}:$${vault:database/creds/my-role#password}@pg-default-rw.db.svc.cluster.local:5432/mydb?sslmode=disable"
      VAULT_ADDR: "http://vault.vault.svc.cluster.local:8200"
      VAULT_SKIP_VERIFY: "false"
      VAULT_AUTH_METHOD: "jwt"
      VAULT_PATH: "kubernetes"
      VAULT_ROLE: "default"
      VAULT_IGNORE_MISSING_SECRETS: "false"
      VAULT_ENV_DAEMON: "true"
      VAULT_ENV_SIG: "SIGTERM"
      VAULT_ENV_DELAY: "2"
```

### Step 5: Mount EmptyDir Volume to `/vault/`
```yaml
persistence:
  vault-env:
    type: emptyDir
    globalMounts:
      - path: /vault/
```

---

## 4. Reverting from Manual Back to Automatic

When cluster CPU headroom is restored and automatic injection is desired:

1. Remove `vault.security.banzaicloud.io/mutate: "skip"`.
2. Keep `vault.security.banzaicloud.io/vault-env-daemon: "true"` (if dynamic renewal is needed).
3. Remove the entire `initContainers.copy-vault-env` block.
4. Remove `/vault/vault-env` prefix from `command` (or remove `command` entirely if using Dockerfile `ENTRYPOINT`).
5. Remove all `VAULT_*` env vars (only keep your app's `vault:...` secrets).
6. Remove `vault-env` from `persistence`.
