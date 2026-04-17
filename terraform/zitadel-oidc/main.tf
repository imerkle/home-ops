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
  default     = "default_app"
}

variable "redirect_uris" {
  type        = list(string)
  description = "List of allowed callback URLs"
}

variable "existing_app_import_id" {
  type        = string
  description = "Optional Zitadel import ID for an existing OIDC app. When set, OpenTofu will import and adopt the app instead of trying to create a duplicate."
  default     = null
  nullable    = true
}

variable "existing_client_secret" {
  type        = string
  description = "Optional client secret for an adopted app. Use this when importing an existing app whose secret cannot be read back from Zitadel."
  default     = null
  nullable    = true
  sensitive   = true
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

# Fetch the generated IDs from the bootstrap secret
data "kubernetes_secret_v1" "bootstrap_ids" {
  metadata {
    name      = "zitadel-bootstrap-ids"
    namespace = "zitadel"
  }
}

locals {
  org_id             = data.kubernetes_secret_v1.bootstrap_ids.data["org_id"]
  project_id         = data.kubernetes_secret_v1.bootstrap_ids.data["project_id"]
  app_import_id      = trimspace(coalesce(var.existing_app_import_id, ""))
  adopted_app_secret = trimspace(coalesce(var.existing_client_secret, "")) != "" ? var.existing_client_secret : null
}

import {
  for_each = local.app_import_id != "" ? { app = local.app_import_id } : {}
  to       = zitadel_application_oidc.app
  id       = each.value
}

resource "zitadel_application_oidc" "app" {
  project_id = local.project_id
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
}

# --- OUTPUTS ---
# These are generic now
output "client_id" {
  value     = zitadel_application_oidc.app.client_id
  sensitive = true
}

output "client_secret" {
  value     = local.adopted_app_secret != null ? local.adopted_app_secret : zitadel_application_oidc.app.client_secret
  sensitive = true
}
