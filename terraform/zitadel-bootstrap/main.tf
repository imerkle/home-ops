terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "2.7.0"
    }
  }
}
provider "kubernetes" {
  # config_path = "~/.kube/config"
  # Configuration depends on your environment (e.g., config_path = "~/.kube/config")
}


# --- INPUT VARIABLES ---
variable "zitadel_domain" {
  type    = string
  default = "zitadel.x3y.space"
}

# Instead of hardcoding "vault", we make the name variable
variable "app_name" {
  type        = string
  description = "The name of the OIDC application (e.g., vault, grafana)"
  default = "default_app"
}

variable "redirect_uris" {
  type        = list(string)
  description = "List of allowed callback URLs"
}

variable "org_id" {
  type        = string
  description = "The ID of the organization"
}

variable "org_name" {
  type        = string
  description = "The name of the organization"
  default     = "homelab"
}

variable "project_name" {
  type        = string
  description = "The name of the project"
  default     = "homelab"
}

data "kubernetes_secret_v1" "zitadel_iam_admin" {
  metadata {
    name      = "iam-admin"
    namespace = "zitadel"
  }
}

# --- PROVIDER ---
provider "zitadel" {
  domain = var.zitadel_domain
  # Ensure this file exists in this folder, or pass content via env var
  # jwt_profile_file = "jwt.json"
  jwt_profile_json = data.kubernetes_secret_v1.zitadel_iam_admin.data["iam-admin.json"]
}

# --- RESOURCES ---

# Check if the organization already exists
data "zitadel_orgs" "existing" {
  name        = var.org_name
  name_method = "TEXT_QUERY_METHOD_EQUALS"
}

locals {
  # If we found an org, use its ID. Otherwise null.
  existing_org_id = length(data.zitadel_orgs.existing.ids) > 0 ? data.zitadel_orgs.existing.ids[0] : null
  # Only create the org if we didn't find it
  create_org      = local.existing_org_id == null
}

# Create the organization ONLY if it doesn't exist
resource "zitadel_organization" "org" {
  count = local.create_org ? 1 : 0
  name  = var.org_name
  # We let Zitadel generate the ID if creating new, or use var.org_id if strictly needed
  # but user said "org id created with doesn't matter".
}

locals {
  # The final org_id to use for downstream resources
  org_id = local.create_org ? zitadel_organization.org[0].id : local.existing_org_id
}

# Check if the project already exists
data "zitadel_projects" "existing" {
  name        = var.project_name
  org_id      = local.org_id
  name_method = "TEXT_QUERY_METHOD_EQUALS"
}

locals {
  existing_project_id = length(data.zitadel_projects.existing.project_ids) > 0 ? data.zitadel_projects.existing.project_ids[0] : null
  create_project      = local.existing_project_id == null
}

# Create project within the organization
resource "zitadel_project" "project" {
  count  = local.create_project ? 1 : 0
  name   = var.project_name
  org_id = local.org_id

  project_role_assertion = true
  has_project_check      = false

  depends_on = [zitadel_organization.org]
}

locals {
  project_id = local.create_project ? zitadel_project.project[0].id : local.existing_project_id
}
