# App Scaffold Template

Use this template to bootstrap a new application in the home-ops cluster.

## Quick Start

1. **Create a new repo** in Forgejo at `forgejo.${DOMAIN1}`
2. **Copy this template** into your new repo
3. **Configure the CI pipeline**:
   - Update the Forgejo webhook to point to the Tekton EventListener
   - Set webhook URL: `http://el-forgejo-webhook.dev-system.svc.cluster.local:8080`
   - Content type: `application/json`
   - Trigger on: Push events
4. **Add your k8s manifests** to `home-ops`:
   - Copy `k8s/` to `kubernetes/apps/prod-system/<your-app>/`
   - Add `<your-app>/ks.yaml` to `kubernetes/apps/prod-system/kustomization.yaml`
5. **Push code** → Tekton builds → Zot stores → Flux deploys

## Directory Structure

```
your-app/
├── Dockerfile              # Multi-stage build
├── .forgejo/
│   └── workflows/
│       └── ci.yaml         # (Optional) Forgejo Actions as alternative to Tekton
├── k8s/
│   ├── ks.yaml             # Flux Kustomization
│   └── app/
│       ├── helmrelease.yaml # App-template HelmRelease
│       ├── kustomization.yaml
│       └── netpol.yaml     # NetworkPolicy
├── src/                    # Your application source
└── README.md
```

## Local Development with Telepresence

```bash
# Connect to the cluster
telepresence connect

# Intercept traffic to your app for local dev
telepresence intercept <your-app> --port <local-port>:<remote-port> --namespace prod-system

# Your local server now receives traffic from the cluster
# When done:
telepresence leave <your-app>
telepresence quit
```

## Database (PostgreSQL)

Your app's HelmRelease includes a `postgres-init` initContainer that automatically creates a database using Vault-injected credentials. The pattern:

```yaml
initContainers:
  init-db:
    image:
      repository: ghcr.io/onedr0p/postgres-init
      tag: "16.4"
    env:
      INIT_POSTGRES_DBNAME: your-app
      INIT_POSTGRES_HOST: "vault:secret/data/pg_default#HOST"
      INIT_POSTGRES_USER: "vault:secret/data/pg_default#USER"
      INIT_POSTGRES_PASS: "vault:secret/data/pg_default#PASSWORD"
      INIT_POSTGRES_SUPER_PASS: "vault:secret/data/pg_default#PASSWORD"
```

## Observability

- **Metrics**: Add a `ServiceMonitor` to scrape your app's `/metrics` endpoint
- **Logs**: Fluent-bit auto-collects stdout/stderr → Victoria Logs
- **Traces**: Configure OTEL_EXPORTER_OTLP_ENDPOINT to the OTel collector
