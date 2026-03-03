---
name: Postgres Vault InitContainer
description: How to make an initContainer for a postgres DB and how to specify inline Vault substitutions using double $$ for Flux HelmReleases.
---

# Postgres InitContainer with Vault Secrets in Flux

This skill demonstrates how to configure an `initContainer` to initialize a PostgreSQL database and how to properly pass inline Vault secret variables using the Banzai Cloud Vault Secrets webhook within a Flux `HelmRelease`.

## Context

When deploying applications using Flux `HelmRelease` and injecting secrets using the Banzai Cloud Vault webhook, you may need to dynamically create databases using an `initContainer` and pass connection strings directly to your application via inline Vault secrets.

Because Flux also evaluates variable substitutions (which use the syntax `${VARIABLE}`), you must escape Vault secret references with a double `$$` to prevent Flux from trying to interpret them before they are passed to the webhook and the pod.

## 1. Initializing a Postgres DB using an InitContainer

To automatically initialize a PostgreSQL database before the main application starts, you can add an `initContainer` that uses the `ghcr.io/onedr0p/postgres-init:16.4` image (or the version you prefer).

### Example Configuration

In your `HelmRelease` `values`, specify the `initContainers` array. This container will run before the main pod and log into your Postgres server to create the configured database.

> [!NOTE]
> Make sure your pod has the proper Vault role annotated so the secrets are injected.
> Example: `vault.security.banzaicloud.io/vault-role: "default"`

```yaml
      initContainers:
        - name: 01-init-db
          image: ghcr.io/onedr0p/postgres-init:16.4
          imagePullPolicy: IfNotPresent
          env:
            - name: INIT_POSTGRES_DBNAME
              value: "your_db_name"
            - name: INIT_POSTGRES_HOST
              value: "vault:secret/data/pg_default#HOST"
            - name: INIT_POSTGRES_USER
              value: "vault:secret/data/pg_default#USER"
            - name: INIT_POSTGRES_PASS
              value: "vault:secret/data/pg_default#PASSWORD"
            - name: INIT_POSTGRES_SUPER_PASS
              value: "vault:secret/data/pg_default#PASSWORD"
```

## 2. Inline Vault Variable Substitution with Double `$$`

When your application requires a single connection URL (rather than individual host/user/password variables), you can use inline Vault references to inject secrets directly into a string.

Because Flux uses single `$` for its own substitutions (e.g., `${DOMAIN1}`), a single `$` followed by braces will be intercepted by the Flux controller, which will fail if the variable doesn't exist in the Flux context.

To pass the literal `${vault:secret...}` string down to the pod, you MUST use double `$$` escapes in a `HelmRelease`. Thus, `$${vault:secret/...}` will be parsed by Flux as `${vault:secret/...}`, which is the exact format required by the Vault Secrets Webhook.

### Example Connection URL

```yaml
        - name: APP_PG_CONNECTION_URL
          value: "postgres://$${vault:secret/data/pg_default#USER}:$${vault:secret/data/pg_default#PASSWORD}@$${vault:secret/data/pg_default#HOST}:5432/your_db_name?sslmode=disable"
```

## Reference Example

For a complete working example, check the `coder` HelmRelease located at:
`kubernetes/apps/dev-system/code-server/coder/hr.yaml`

It demonstrates both the `initContainer` (to create the `coder` database) and the double `$$` substitution for the `CODER_PG_CONNECTION_URL` variable.
