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

# Create R2 bucket for email storage
resource "cloudflare_r2_bucket" "email_inbox" {
  account_id = data.cloudflare_zone.current.account_id
  name       = "home-ops-email-inbox"
}

# Create the Cloudflare Worker script
resource "cloudflare_workers_script" "email_receiver" {
  account_id = data.cloudflare_zone.current.account_id
  name       = "email-receiver"
  content    = file("${path.module}/worker.js")
  module     = true

  r2_bucket_binding {
    name        = "EMAIL_BUCKET"
    bucket_name = cloudflare_r2_bucket.email_inbox.name
  }
}

# Create a catch-all routing rule to forward to the Worker
resource "cloudflare_email_routing_catch_all" "catch_all" {
  zone_id = local.zone_id
  name    = "Catch-all forward rule"
  enabled = true

  matcher {
    type = "all"
  }

  action {
    type  = "worker"
    value = [cloudflare_workers_script.email_receiver.name]
  }

  # Ensure settings are enabled first
  depends_on = [cloudflare_email_routing_settings.main]
}

