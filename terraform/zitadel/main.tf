variable "zitadel_token" {
  type      = string
  sensitive = true
}

variable "zitadel_domain" {
  type    = string
  default = "http://zitadel.x3y.space"
}

provider "zitadel" {
  domain = var.zitadel_domain
  token  = "eb0f4sQyyNY8YSbcuE3MYqTZi2R9l6vNjdieqfsIoockW0-IzfQM0devxx616ZvqRCh-HLw"
}

# 1. Get the Project (or create a new one)
data "zitadel_project" "default" {
  name   = "General" # Or your specific project name
  org_id = "YOUR_ORG_ID"
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
    "http://localhost:8200/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback" # For CLI login
  ]

  dev_mode = true # Set to false in production with HTTPS
}

# 3. Output credentials for Vault
output "vault_client_id" {
  value = zitadel_application_oidc.vault.client_id
}

output "vault_client_secret" {
  value     = zitadel_application_oidc.vault.client_secret
  sensitive = true
}