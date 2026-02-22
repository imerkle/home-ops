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

# Create project within the organization
resource "zitadel_project" "project" {
  name   = var.app_name
  org_id = local.org_id

  project_role_assertion = true
  has_project_check      = false

  depends_on = [zitadel_organization.org]
}

resource "zitadel_application_oidc" "app" {
  project_id = zitadel_project.project.id
  org_id     = local.org_id

  # Use the variable name
  name = var.app_name

  response_types    = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types       = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  auth_method_type  = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type = "OIDC_TOKEN_TYPE_BEARER"

  id_token_userinfo_assertion = true

  # Use the variable URIs
  redirect_uris = var.redirect_uris

  dev_mode = true

  id_token_role_assertion      = false
  access_token_role_assertion  = false
  additional_origins           = []
  post_logout_redirect_uris    = []
  skip_native_app_success_page = false
  depends_on = [
    zitadel_project.project
  ]
}

# --- OUTPUTS ---
# These are generic now
output "client_id" {
  value     = zitadel_application_oidc.app.client_id
  sensitive = true
}

output "client_secret" {
  value     = zitadel_application_oidc.app.client_secret
  sensitive = true
}