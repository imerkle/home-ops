terraform {
  required_providers {
    zitadel = {
      source = "zitadel/zitadel"
      version = "2.3.0"
    }
  }
}

# variable "zitadel_token" {
#   type      = string
#   sensitive = true
# }

variable "zitadel_domain" {
  type    = string
  default = "zitadel.x3y.space"
}

provider "zitadel" {
  domain = var.zitadel_domain
  jwt_profile_file  = "jwt.json"
}

# 1. Get the Project (or create a new one)
data "zitadel_project" "default" {
  # org_id = "350837510680674408"
  project_id = "351115276617646240"
}

# 2. Create the OIDC Application for Vault
resource "zitadel_application_oidc" "vault" {
  project_id = data.zitadel_project.default.id
  org_id     = data.zitadel_project.default.org_id
  name       = "vault-oidc"

  # Vault uses "Code" flow for OIDC login
  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types    = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"

  # Standard OIDC Scopes
  access_token_type = "OIDC_TOKEN_TYPE_BEARER"
  id_token_userinfo_assertion = true

  # Redirect URIs for your Vault instance
  # Replace with your actual Vault address
  redirect_uris = [
    "http://vault.x3y.space/ui/vault/auth/oidc/oidc/callback",
    # "http://localhost:8150/oidc/callback" # For CLI login
  ]

  dev_mode = true # Set to false in production with HTTPS
}

# 3. Output credentials for Vault
output "vault_client_id" {
  value = zitadel_application_oidc.vault.client_id
  sensitive = true
}

output "vault_client_secret" {
  value     = zitadel_application_oidc.vault.client_secret
  sensitive = true
}