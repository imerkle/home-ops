variable "gcp_project_id" {
  description = "GCP project ID where resources will be created (defaults to value from Vault if not provided)"
  type        = string
  default     = null
}

variable "gcp_region" {
  description = "GCP region for networking resources"
  type        = string
  default     = "us-west1"
}

variable "gcp_zone" {
  description = "GCP zone for the compute instance"
  type        = string
  default     = "us-west1-a"
}

variable "machine_type" {
  description = "GCE machine type; default is Always Free eligible in supported US regions"
  type        = string
  default     = "e2-micro"
}

variable "image_project" {
  description = "GCP image project"
  type        = string
  default     = "debian-cloud"
}

variable "image_family" {
  description = "GCP image family"
  type        = string
  default     = "debian-12"
}

variable "instance_name" {
  description = "Compute instance name"
  type        = string
  default     = "mail-relay"
}

variable "hostname" {
  description = "Host label for mail relay, e.g. mail"
  type        = string
  default     = "mail"
}

variable "mail_domain" {
  description = "Primary mail domain, e.g. example.com"
  type        = string
}

variable "relay_target_mesh_ip" {
  description = "Headscale/Tailscale IP of Stalwart node"
  type        = string
}

variable "relay_target_port" {
  description = "Destination SMTP port on Stalwart"
  type        = number
  default     = 25
}

variable "headscale_url" {
  description = "Headscale URL used by clients, e.g. http://<vps-public-ip>:8080 or https://headscale.example.com"
  type        = string
}

variable "headscale_version" {
  description = "Headscale version to install"
  type        = string
  default     = "0.26.0"
}

variable "headscale_listen_port" {
  description = "Headscale listen port on the VPS"
  type        = number
  default     = 8080
}

variable "headscale_user" {
  description = "Headscale user to create preauth keys for"
  type        = string
  default     = "homelab"
}

variable "tailscale_advertise_tag" {
  description = "Optional tag to advertise when joining headscale/tailscale"
  type        = string
  default     = ""
}

variable "ssh_username" {
  description = "SSH username for connecting to the instance"
  type        = string
  default     = "debian"
}

variable "ssh_authorized_keys" {
  description = "SSH public key(s) for the instance user"
  type        = string
}

variable "subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.80.10.0/24"
}

variable "create_cloudflare_records" {
  description = "Set true to create A/MX/TXT records in Cloudflare"
  type        = bool
  default     = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit access (defaults to value from Vault if not provided)"
  type        = string
  default     = null
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID (defaults to value from Vault if not provided)"
  type        = string
  default     = null
}

variable "mx_priority" {
  description = "MX priority"
  type        = number
  default     = 10
}

variable "spf_record" {
  description = "SPF TXT value"
  type        = string
  default     = "v=spf1 mx -all"
}

variable "dmarc_record" {
  description = "DMARC TXT value; empty disables record creation"
  type        = string
  default     = ""
}

variable "use_vault" {
  description = "Whether to use Vault for credentials (when false, uses tfvars/environment variables)"
  type        = bool
  default     = false
}
