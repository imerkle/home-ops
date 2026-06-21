terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30.0"
    }
  }
}

provider "kubernetes" {}

data "kubernetes_secret_v1" "vault_unseal_keys" {
  metadata {
    name      = "vault-unseal-keys"
    namespace = "vault"
  }
}

provider "vault" {
  address = "http://vault.vault:8200"
  token   = data.kubernetes_secret_v1.vault_unseal_keys.data["vault-root"]
}

locals {
  static_roles = [
    { name = "synapse-static", username = "synapse_user" },
    { name = "mas-static", username = "mas_user" },
    { name = "atuin-static", username = "atuin_user" },
    { name = "vaultwarden-static", username = "vaultwarden_user" },
    { name = "zealot-static", username = "zealot_user" },
    { name = "zitadel-static", username = "zitadel_user" },
    { name = "forgejo-static", username = "forgejo_user" },
    { name = "coder-static", username = "coder_user" },
    { name = "litellm-static", username = "litellm_user" },
    { name = "keto-static", username = "keto_user" },
    { name = "temporal-static", username = "temporal_user" },
    { name = "game-fetcher-static", username = "game_fetcher_user" },
    { name = "settings-server-static", username = "settings_server_user" }
  ]
}

resource "vault_database_secret_backend_static_role" "roles" {
  for_each            = { for r in local.static_roles : r.name => r }
  backend             = "database"
  name                = each.value.name
  db_name             = "pg-default"
  username            = each.value.username
  rotation_period     = "604800" # 7 days in seconds
  rotation_statements = ["ALTER ROLE \"{{name}}\" WITH PASSWORD '{{password}}';"]
}
