# SKILL: Flux Sync and Git Push

When you make configuration changes to the cluster (e.g., editing Kubernetes manifests, HelmReleases, Terraform files, or other resources in this repository), you MUST follow these steps to ensure the cluster applies the changes immediately:

1. **Commit and Push**: Ensure all changes are committed and pushed to the git repository.
   ```bash
   git add .
   git commit -m "chore: update cluster config"
   git push
   ```

2. **Trigger Flux Reconciliation**: Force Flux to fetch the latest changes from the repository immediately, rather than waiting for the next polling interval. Run the following command:
   ```bash
   flux reconcile source git flux-system -n flux-system
   ```

## Why this is required
Flux operates on a pull-based GitOps model. By default, it polls the git repository at a set interval. Pushing your changes and manually triggering a reconciliation of the `flux-system` GitRepository forces Flux to pull your latest commit and apply the changes to the cluster immediately. This gives you instant feedback and prevents delays during development or troubleshooting.
