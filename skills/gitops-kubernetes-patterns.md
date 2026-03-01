---
name: gitops-kubernetes-patterns
description: GitOps Kubernetes patterns from home-ops repository
version: 1.0.0
source: local-git-analysis
analyzed_commits: 100
---

# GitOps Kubernetes Patterns

## GitOps Architecture

This repository implements GitOps for Kubernetes cluster management using FluxCD with the following characteristics:

### FluxCD Components
- **Kustomization (ks.yaml)**: FluxCD resources that define what to sync from Git
- **HelmRelease**: Deploy Helm charts declaratively
- **OCIRepository**: Pull Helm charts from OCI registries
- **HelmRepository**: Define Helm chart repositories
- **GitRepository**: Define Git sources (for external sources)

### Directory Structure Pattern
```
apps/{namespace}/{application}/
├── app/
│   ├── helmrelease.yaml      # Deploy the application
│   ├── kustomization.yaml    # Kustomize configuration
│   ├── httproute.yaml        # Gateway API ingress
│   ├── netpol.yaml           # Network policies
│   ├── dnsendpoint.yaml      # ExternalDNS endpoints
│   ├── externalsecret.yaml   # Encrypted secrets
│   └── {other-resources}.yaml
├── ks.yaml                 # FluxCD Kustomization resource
└── kustomization.yaml      # Root kustomization
```

## Application Deployment Patterns

### Standard Deployment Flow
1. Create application manifest in `apps/{namespace}/{app}/app/`
2. Create FluxCD Kustomization resource (`ks.yaml`)
3. Add application to parent kustomization (`apps/{namespace}/kustomization.yaml`)
4. Add namespace to main apps kustomization if new

### Common Resource Types
- **HelmRelease**: Most common deployment method
- **NetworkPolicies**: Security through network segmentation
- **HTTPRoutes**: Gateway API for ingress
- **ExternalSecrets**: Secret management with external providers
- **DNSEndpoints**: ExternalDNS integration

## GitOps Workflow

### Update Process
- Direct changes to manifests in Git repository
- FluxCD automatically reconciles cluster state
- Most frequent updates to configuration files (`config.yaml`)
- Network policy adjustments as needed
- Helm chart version updates

### Security Patterns
- SOPS for encrypting secrets (`*.sops.yaml`)
- Network policies for service isolation
- External secrets from Vault or other providers
- OIDC integration for authentication

## Namespace Management

### Naming Convention
- `{purpose}-system`: Dedicated namespaces for different purposes
  - `dev-system`: Development tools
  - `home-system`: Home services
  - `kube-system`: Kubernetes system components
  - `network/observability/storage`: Infrastructure services

### Namespace Resources
- `apps/{namespace}/namespace.yaml`: Namespace definition
- `apps/{namespace}/kustomization.yaml`: Includes all apps in namespace
- Individual applications in `apps/{namespace}/{app}/`

## Monitoring and Observability

### Service Discovery
- Gateway API (HTTPRoute) for ingress
- Service monitoring through dedicated components
- Health checking via Gatus or similar tools

### Resource Optimization
- Goldilocks for resource recommendation
- Vertical Pod Autoscaler (VPA) for automatic scaling
- Network policies for traffic optimization

## Common Applications

### Development Tools
- **code-server**: VS Code in browser
- **litellm**: LLM proxy service
- **open-webui**: Web interface for LLMs
- **forgejo**: Self-hosted Git service

### Home Services
- **home-assistant**: Home automation
- **frigate**: Video processing for cameras
- **stalwart**: Email server
- **matrix**: Communication platform

### Infrastructure
- **vault**: Secrets management
- **rook-ceph**: Storage cluster
- **vyos**: Network router configuration
- **kubevirt**: Virtual machine management