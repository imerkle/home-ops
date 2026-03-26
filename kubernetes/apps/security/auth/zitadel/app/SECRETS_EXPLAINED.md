# Zitadel Secrets & Lifecycle Explanation

Here is how Zitadel secrets and resources are created in the Kubernetes Helm chart:

### 1. Secrets & ConfigMaps (Created First)
When Helm installs or upgrades, it creates the base configuration resources first:
- **`zitadel-secrets`**: The primary secret created by the Helm chart. It contains sensitive data from `values.yaml` (e.g., `MasterKey`, `Database.Password`, `TraceIdSharedKey`).
- **`zitadel-config`**: A ConfigMap containing the `zitadel.yaml` runtime configuration.

### 2. Initialization Jobs (Run Sequentially)
After the secrets and configmaps are applied, Helm triggers lifecycle hooks (Jobs):
1. **`zitadel-init`** (Job):
   - Runs `zitadel init`.
   - Connects to the database using credentials from `zitadel-secrets`.
   - Sets up the database schema and migrations.
   - **Order**: Must complete successfully before the next step.

2. **`zitadel-setup`** (Job):
   - Runs `zitadel setup`.
   - Seeds initial data (default organization, policies, IAM owner).
   - Uses `ZITADEL_FIRSTINSTANCE_ORG_HUMAN_*` env vars to create the initial admin user.
   - **Order**: Runs after `zitadel-init` succeeds.

### 3. Application Deployment
- **`zitadel`** (Deployment/StatefulSet):
  - The main application pods start.
  - They mount `zitadel-secrets` and `zitadel-config`.
  - They wait for readiness checks (often dependent on setup completion).

### Regarding your `login-client` Secret:
The `login-client` secret in `loginclient.sops.yaml` is **not** created by the Helm chart. It is a custom secret defined in your repository (managed by Flux/SOPS). It is likely intended for external tools (like Terraform) to authenticate with Zitadel, but runs independently of the Helm chart's lifecycle.
