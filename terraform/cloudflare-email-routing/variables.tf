variable "zone_id" {
  description = "Cloudflare Zone ID (if not provided, will be read from Vault secrets)"
  type        = string
  default     = ""
}

variable "mail_domain" {
  description = "The root domain used for email (e.g., example.com)"
  type        = string
}

variable "destination_email" {
  description = "The actual destination email address to forward to"
  type        = string
}
