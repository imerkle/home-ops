---
name: home-ops-patterns
description: Home operations patterns from home-ops repository
version: 1.0.0
source: local-git-analysis
analyzed_commits: 100
---

# Home Ops Patterns

## Repository Structure

This repository manages home infrastructure using GitOps with the following main areas:

- `kubernetes/` - FluxCD manifests for Kubernetes cluster management
- `terraform/` - Infrastructure as Code for cloud resources
- `ansible/` - Infrastructure automation (if present)

## Kubernetes Architecture

### Directory Structure
```
kubernetes/
├── apps/                 # Application workloads organized by namespace
│   ├── dev-system/       # Development tools and services
│   ├── home-system/      # Home services (media, IoT, etc.)
│   ├── kube-system/      # Kubernetes system components
│   ├── observability/    # Monitoring and logging stack
│   └── network/          # Network-related components
├── components/           # Reusable Kubernetes components
├── flux/                 # FluxCD cluster configuration
└── archive/              # Archived/deprecated applications
```

### Application Organization
- Applications are organized by namespace (e.g., `dev-system`, `home-system`)
- Each application follows the pattern: `app-name/app/` with individual resources
- Kustomize is used extensively for configuration management
- FluxCD Kustomization resources (`ks.yaml`) tie everything together

### GitOps Workflow
- Changes are made directly to manifests in the repository
- FluxCD reconciles the cluster state with the repository
- Applications use HelmReleases, OCIRepositories, and other FluxCD CRDs
- Secrets are managed with SOPS encryption (`*.sops.yaml`)

## Commit Conventions

This repository uses a mix of commit styles:
- `feat(scope): description` - New features (e.g., "feat(litellm): Add netpol for accessing MCP servers")
- `fix(scope): description` - Bug fixes (e.g., "fix(litellm): update netpol ingress")
- `t` - Temporary/minor changes (common pattern in this repo)

## Common Application Patterns

### Standard Application Structure
```
apps/{namespace}/{app-name}/
├── app/
│   ├── helmrelease.yaml      # Helm release configuration
│   ├── kustomization.yaml    # Kustomize overlay
│   ├── httproute.yaml        # Gateway API route
│   ├── netpol.yaml           # Network policies
│   └── config.yaml           # Application config
├── ks.yaml                 # FluxCD Kustomization
└── kustomization.yaml      # Base kustomization
```

### Frequently Changed Files
- `config.yaml` - Application configuration files (most frequently updated)
- `helmrelease.yaml` - Helm chart configurations
- `netpol.yaml` - Network policy adjustments
- `kustomization.yaml` - Kustomize overlays
- `httproute.yaml` - Route configurations

## Infrastructure Management

### Terraform Usage
- Separate directories for different infrastructure concerns
- Provider-specific configurations (Zitadel, Oracle Cloud Infrastructure)
- State management with Terraform backend
- Bootstrap configurations for initial setup

### Services Categories
- **Development**: code-server, litellm, open-webui, ollama-ui
- **Home Automation**: home-assistant, frigate, stalwart (mail server)
- **Communication**: matrix, rustdesk
- **Networking**: vyos router, multus CNI, kubevirt VMs
- **Observability**: goldilocks, VPA
- **Storage**: rook-ceph clusters

## Operational Patterns

### Namespace Management
- Dedicated namespaces for different purposes
- Namespace manifests in `apps/{namespace}/namespace.yaml`
- Consistent naming convention with `-system` suffix

### Security Practices
- SOPS for secret encryption
- Network policies for service isolation
- External secrets management
- OIDC integration (Zitadel)

### Monitoring & Observability
- Service monitoring through Gatus
- Resource optimization with Goldilocks
- Vertical Pod Autoscaler (VPA)
- Network policies for traffic control