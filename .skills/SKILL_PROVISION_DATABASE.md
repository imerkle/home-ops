---
name: provision-app-database
description: How to provision dynamic PostgreSQL databases and Vault secrets using Crossplane AppDatabase
version: 1.0.0
---

# Provisioning Application Databases with Crossplane and Vault

## Overview

This repository uses **Crossplane** and **Vault** to fully automate the provisioning of PostgreSQL databases, roles, and dynamic credentials. Instead of manually creating databases, roles, and static `ExternalSecret` configurations, you can use the custom `AppDatabase` resource.

When you create an `AppDatabase`, Crossplane automatically:
1. Provisions a new `Database` in PostgreSQL.
2. Provisions a new `Role` (the application's group role) and assigns it as the Owner of the database (granting all schema and table privileges).
3. Creates a dynamic `SecretBackendRole` in Vault, which configures Vault to automatically generate temporary database credentials for applications that assume the app's group role.

## Step-by-step

### 1. Create the `appdatabase.yaml`

In your application's `app/` directory (e.g., `kubernetes/apps/<namespace>/<app-name>/app/appdatabase.yaml`), create the following resource:

```yaml
---
apiVersion: home.arpa/v1alpha1
kind: AppDatabase
metadata:
  name: <app-name>-db
  namespace: <namespace>
spec:
  # The name of the database to create in PostgreSQL
  databaseName: <app_name>_db
  # The group role in PostgreSQL that will own the database
  groupRole: <app-name>-role
  # (Optional) Whether the app will create schemas itself (default is false)
  schemaCreate: false
  # (Optional) Whether to create the database or just the roles (default is true)
  createDb: true
```

### 2. Include the AppDatabase in Kustomization

Add `./appdatabase.yaml` to your application's `app/kustomization.yaml` resources list:

```yaml
resources:
  - ./appdatabase.yaml
  - ./helmrelease.yaml
```

### 3. Consume the Dynamic Secrets in `helmrelease.yaml`

The Banzai Cloud Vault webhook injects the generated database credentials directly into your application's Pod at runtime using a dynamic Vault role.

**Step A: Configure Vault annotations**

In your `helmrelease.yaml`, under `pod` annotations, specify the Vault role. The Vault role name is always the `<appdatabase-name>-role` (not the groupRole).

```yaml
    controllers:
      <app-name>:
        annotations:
          vault.security.banzaicloud.io/vault-role: <appdatabase-name>-role
```

*(For example, if your AppDatabase is named `atuin-db`, the vault role is `atuin-db-role`.)*

**Step B: Inject Environment Variables**

Use the `vault:` prefix in your environment variables to dynamically resolve the `username` and `password` from the Vault endpoint. The vault path is always `database/creds/<appdatabase-name>-role`.

```yaml
        containers:
          app:
            env:
              DB_HOST: pg-default-rw.db.svc.cluster.local:5432
              DB_NAME: <app_name>_db
              DB_USER: "vault:database/creds/<appdatabase-name>-role#username"
              DB_PASSWORD: "vault:database/creds/<appdatabase-name>-role#password"
              
              # Alternatively, if your app requires a full connection string:
              DB_URI: postgres://${vault:database/creds/<appdatabase-name>-role#username}:${vault:database/creds/<appdatabase-name>-role#password}@pg-default-rw.db.svc.cluster.local:5432/<app_name>_db?sslmode=disable
```

## How It Works Under the Hood

1. **Database & Role Creation**: The `AppDatabase` claim creates a Crossplane `XAppDatabase` composite resource. This generates a PostgreSQL `Database` and `Role` via the Upbound PostgreSQL Provider (`provider-sql`).
2. **Privileges**: The newly created PostgreSQL `Role` (e.g. `atuin-role`) is assigned as the `Owner` of the PostgreSQL `Database`. This eliminates the need for complex database and schema-level grants, giving the role full access to the database and its default `public` schema.
3. **Vault Integration**: Crossplane creates a Vault `SecretBackendRole` using the Upbound Vault Provider (`provider-vault`). The `creationStatements` configured in Vault dynamically inject the correct hyphens and syntax: `CREATE ROLE "{{name}}" ... INHERIT; GRANT "<groupRole>" TO "{{name}}";`.
4. **Credential Rotation**: When the Vault Webhook intercepts your app's Pod creation, it authenticates with Vault and requests credentials from `database/creds/<app-role>`. Vault generates a random user (with a TTL), applies the `creationStatements` in PostgreSQL, and returns the username/password to the webhook, which injects them directly into the Pod.

> [!WARNING]
> **Long-Lived Pods and Credential Expiration**
> By default, the Banzai Cloud Mutating Webhook performs an inline mutation that hardcodes the evaluated secrets directly into the Pod definition at creation time. If the Vault credentials have a TTL (e.g. 1 hour or 7 days) and the pod lives longer than the TTL, the credentials will expire and the pod will crash with `password authentication failed`.
> 
> For long-lived applications that require continuous database connections, you **MUST** bypass the inline mutation and manually inject the `vault-env` daemon. This ensures the environment variables are re-evaluated dynamically on process restart.

### Manual Injection Pattern (For Long-Lived Pods)

If your app crashes due to expired keys or is expected to run indefinitely, apply the following manual injection pattern instead of relying on the default webhook:

```yaml
    podAnnotations:
      vault.security.banzaicloud.io/mutate: "skip"
      vault.security.banzaicloud.io/vault-env-daemon: "true"
```

And update your Deployment template to wrap your application's entrypoint with `vault-env`:

```yaml
    spec:
      template:
        spec:
          volumes:
            - name: vault-env
              emptyDir: {}
          initContainers:
            - name: copy-vault-env
              image: ghcr.io/bank-vaults/vault-env:v1.21.3
              command: ["sh", "-c", "cp /usr/local/bin/vault-env /vault/"]
              volumeMounts:
                - name: vault-env
                  mountPath: /vault/
          containers:
            - name: app
              # Wrap the main process with vault-env
              command: ["/vault/vault-env", "your", "app", "command"]
              volumeMounts:
                - name: vault-env
                  mountPath: /vault/
              env:
                # You MUST provide these variables manually when bypassing the webhook
                - name: VAULT_ADDR
                  value: "http://vault.vault.svc.cluster.local:8200"
                - name: VAULT_SKIP_VERIFY
                  value: "false"
                - name: VAULT_AUTH_METHOD
                  value: "jwt"
                - name: VAULT_PATH
                  value: "kubernetes"
                - name: VAULT_ROLE
                  value: "default"
                - name: VAULT_IGNORE_MISSING_SECRETS
                  value: "false"
```
