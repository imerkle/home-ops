terraform {
  required_providers {
    zitadel = {
      source = "zitadel/zitadel"
      version = "2.3.0"
    }
  }
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
}

variable "redirect_uris" {
  type        = list(string)
  description = "List of allowed callback URLs"
}

# Use a default project/org or make them variable if they change often
variable "org_id" {
  type    = string
  default = "351115276617580704"
}

variable "project_id" {
  type    = string
  default = "351291229247373498"
}

# --- PROVIDER ---
provider "zitadel" {
  domain           = var.zitadel_domain
  # Ensure this file exists in this folder, or pass content via env var
  jwt_profile_file = "jwt.json"
}

# --- RESOURCES ---
resource "zitadel_application_oidc" "app" {
  project_id = var.project_id
  org_id     = var.org_id

  # Use the variable name
  name       = var.app_name

  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type = "OIDC_TOKEN_TYPE_BEARER"

  id_token_userinfo_assertion = true

  # Use the variable URIs
  redirect_uris = var.redirect_uris

  dev_mode = true

  id_token_role_assertion = false
  access_token_role_assertion = false
  additional_origins = []
  post_logout_redirect_uris = []
  skip_native_app_success_page = false
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