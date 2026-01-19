terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "2.3.0"
    }
  }
}
provider "kubernetes" {
  # Configuration depends on your environment (e.g., config_path = "~/.kube/config")
}
data "kubernetes_secret" "zitadel_admin_key" {
  metadata {
    name      = "iam-admin-pat"
    namespace = "zitadel"
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
  default = "default_app"
}

variable "redirect_uris" {
  type        = list(string)
  description = "List of allowed callback URLs"
}

# --- PROVIDER ---
provider "zitadel" {
  domain = var.zitadel_domain
  # Ensure this file exists in this folder, or pass content via env var
  # jwt_profile_file = "jwt.json"
  jwt_profile_json = data.kubernetes_secret.zitadel_admin_key.data["iam-admin.json"]
}

# --- RESOURCES ---

# Create organization
resource "zitadel_org" "org" {
  name  = var.app_name
  # state = "ORG_STATE_ACTIVE"
}

# Create project within the organization
resource "zitadel_project" "project" {
  name   = var.app_name
  org_id = zitadel_org.org.id

  project_role_assertion = true
  has_project_check      = true
}

resource "zitadel_application_oidc" "app" {
  project_id = zitadel_project.project.id
  org_id     = zitadel_organization.org.id

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
  value     = zitadel_application_oidc.app.client_secret
  sensitive = true
}