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



