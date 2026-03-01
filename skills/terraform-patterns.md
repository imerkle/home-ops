---
name: terraform-patterns
description: Terraform infrastructure patterns from home-ops repository
version: 1.0.0
source: local-git-analysis
analyzed_commits: 100
---

# Terraform Patterns

## Infrastructure Structure

This repository manages infrastructure as code using Terraform with the following patterns:

### Directory Organization
```
terraform/
├── zitadel/              # Zitadel identity management
├── zitadel-oidc/         # OIDC provider configurations
├── zitadel-bootstrap/    # Initial Zitadel setup
├── mail-relay-gcp-headscale/ # Mail relay and VPN infrastructure
└── {service-name}/       # Other infrastructure services
```

## Terraform Management Patterns

### State Management
- Local state files with `.tfstate` extension
- Backend configuration for remote state (likely in `.terraform/` directories)
- Provider-specific state files in `.terraform/` directory

### Provider Usage
- **Zitadel**: Identity and access management provider
- **Oracle Cloud Infrastructure**: Cloud resources (OCI)
- **Kubernetes**: Kubernetes cluster resources
- **Random**: Random resource generation for unique identifiers

### Module Organization
- Separate directories for each infrastructure component
- Main configuration files: `main.tf`, `variables.tf`, `outputs.tf`
- Provider configuration files: `provider.tf` or in `main.tf`
- Variable files: `terraform.tfvars` for environment-specific values

## Common Terraform Patterns

### Bootstrap Configurations
- Separate bootstrap modules for initial setup
- Sequential dependency management
- Identity and access configuration first
- Resource creation in dependency order

### OIDC Integration
- OIDC provider setup for authentication
- Application registration in identity providers
- Client configuration for various services
- Secret management for client credentials

### Infrastructure Components
- Identity management (Zitadel)
- Cloud resources (GCP, OCI)
- Network infrastructure
- Security and access controls

## Infrastructure as Code Best Practices

### Version Control
- Terraform code stored in Git repository
- Infrastructure changes tracked with Git
- Configuration files encrypted with SOPS when containing secrets
- State files excluded from version control

### Provider Management
- Provider versions locked for consistency
- Provider-specific configurations in dedicated files
- Multiple providers coordinated for complex setups
- Provider authentication through environment variables or files

### Variable Management
- Environment-specific variables in `terraform.tfvars`
- Sensitive variables handled through external secrets
- Consistent variable naming conventions
- Default values for optional parameters