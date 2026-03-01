terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
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

provider "google" {
  project     = coalesce(var.gcp_project_id, lookup(data.vault_generic_secret.gcp_credentials.data, "gcp_project_id", null))
  region      = var.gcp_region
  zone        = var.gcp_zone
  # For Vault KV v2, the actual data is in the "data" key of the response
  # If GCP credentials are nested under a 'gcp' key in the secret
  credentials = jsonencode(
    jsondecode(base64decode(lookup(data.vault_generic_secret.gcp_credentials.data, "gcp", base64encode("{}"))))
  )
}

provider "cloudflare" {
  api_token = coalesce(var.cloudflare_api_token, lookup(data.vault_generic_secret.cloudflare_secrets.data, "DNS1_TOKEN", null))
}

provider "vault" {
  address = "http://vault.vault:8200"

  # Configure for Kubernetes authentication when running in-cluster
  # This will use the pod's service account token automatically when running in tofu-controller
}

data "vault_generic_secret" "gcp_credentials" {
  path = "secret/ai"
}

data "vault_generic_secret" "cloudflare_secrets" {
  path = "secret/cloudflare"
}

locals {
  relay_hostname = "${var.hostname}.${var.mail_domain}"
}

data "google_compute_image" "os_image" {
  family  = var.image_family
  project = var.image_project
}

resource "google_compute_network" "mail" {
  name                    = "mail-relay-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "mail" {
  name          = "mail-relay-subnetwork"
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.mail.id
}

resource "google_compute_firewall" "mail_ingress" {
  name    = "mail-relay-ingress"
  network = google_compute_network.mail.name

  allow {
    protocol = "tcp"
    ports    = ["22", "25", tostring(var.headscale_listen_port)]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "mail_relay" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.os_image.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mail.id

    access_config {}
  }

  metadata = {
    ssh-keys = "${var.ssh_username}:${var.ssh_authorized_keys}"
    user-data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
      hostname                = var.hostname
      mail_domain             = var.mail_domain
      relay_target_mesh_ip    = var.relay_target_mesh_ip
      relay_target_port       = var.relay_target_port
      headscale_url           = var.headscale_url
      headscale_version       = var.headscale_version
      headscale_listen_port   = var.headscale_listen_port
      headscale_user          = var.headscale_user
      tailscale_advertise_tag = var.tailscale_advertise_tag
    })
  }
}

resource "cloudflare_record" "mail_a" {
  count   = var.create_cloudflare_records ? 1 : 0
  zone_id = try(coalesce(var.cloudflare_zone_id, lookup(data.vault_generic_secret.cloudflare_secrets.data, "DNS1_ZONE_ID", null)), var.cloudflare_zone_id)
  name    = var.hostname
  type    = "A"
  value   = google_compute_instance.mail_relay.network_interface[0].access_config[0].nat_ip
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "mail_mx" {
  count    = var.create_cloudflare_records ? 1 : 0
  zone_id  = try(coalesce(var.cloudflare_zone_id, lookup(data.vault_generic_secret.cloudflare_secrets.data, "DNS1_ZONE_ID", null)), var.cloudflare_zone_id)
  name     = var.mail_domain
  type     = "MX"
  value    = local.relay_hostname
  priority = var.mx_priority
  ttl      = 300
}

resource "cloudflare_record" "spf" {
  count   = var.create_cloudflare_records ? 1 : 0
  zone_id = try(coalesce(var.cloudflare_zone_id, lookup(data.vault_generic_secret.cloudflare_secrets.data, "DNS1_ZONE_ID", null)), var.cloudflare_zone_id)
  name    = var.mail_domain
  type    = "TXT"
  value   = var.spf_record
  ttl     = 300
}

resource "cloudflare_record" "dmarc" {
  count   = var.create_cloudflare_records && var.dmarc_record != "" ? 1 : 0
  zone_id = try(coalesce(var.cloudflare_zone_id, lookup(data.vault_generic_secret.cloudflare_secrets.data, "DNS1_ZONE_ID", null)), var.cloudflare_zone_id)
  name    = "_dmarc.${var.mail_domain}"
  type    = "TXT"
  value   = var.dmarc_record
  ttl     = 300
}

output "vps_public_ip" {
  value = google_compute_instance.mail_relay.network_interface[0].access_config[0].nat_ip
}

output "mail_relay_fqdn" {
  value = local.relay_hostname
}

output "mx_target" {
  value = local.relay_hostname
}

output "headscale_authkey_read_cmd" {
  value = "ssh ${var.ssh_username}@${google_compute_instance.mail_relay.network_interface[0].access_config[0].nat_ip} 'sudo cat /root/headscale-preauth-key.txt'"
}

# Note: The preauth key is generated on the server and available via the SSH command
# To retrieve it manually: terraform output headscale_authkey_read_cmd
