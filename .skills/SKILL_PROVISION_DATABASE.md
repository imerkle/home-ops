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
