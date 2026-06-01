terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
}

provider "cloudflare" {
  api_token = lookup(data.vault_generic_secret.cloudflare_secrets.data, "EMAIL_ROUTE_TOKEN", null)
}

provider "vault" {
  address          = "http://vault.vault:8200"
  skip_child_token = true

  auth_login {
    path = "auth/kubernetes/login"
    parameters = {
      role = "default"
      jwt  = file("/var/run/secrets/kubernetes.io/serviceaccount/token")
    }
  }
}

data "vault_generic_secret" "cloudflare_secrets" {
  path = "secret/cloudflare"
}

locals {
  zone_id = try(coalesce(var.zone_id, lookup(data.vault_generic_secret.cloudflare_secrets.data, "DNS1_ZONE_ID", null)), var.zone_id)
}

data "cloudflare_zone" "current" {
  zone_id = local.zone_id
}

# Enable Email Routing (automatically creates Cloudflare's required MX and TXT records)
resource "cloudflare_email_routing_settings" "main" {
  zone_id = local.zone_id
  enabled = "true"
}

# Register the destination email address
resource "cloudflare_email_routing_address" "destination" {
  account_id = data.cloudflare_zone.current.account_id
  email      = var.destination_email
}

# Create a catch-all routing rule to forward to the destination address
resource "cloudflare_email_routing_rule" "catch_all" {
  zone_id = local.zone_id
  name    = "Catch-all forward rule"
  enabled = true

  matcher {
    type = "all"
  }

  action {
    type  = "forward"
    value = [cloudflare_email_routing_address.destination.email]
  }

  # Ensure settings are enabled first
  depends_on = [cloudflare_email_routing_settings.main]
}

