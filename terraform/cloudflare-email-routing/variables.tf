variable "account_id" {
  description = "Cloudflare Account ID (if not provided, will be read from Vault secrets)"
  type        = string
  default     = ""
}

variable "zone_id" {
  description = "Cloudflare Zone ID (if not provided, will be read from Vault secrets)"
  type        = string
  default     = ""
}

variable "mail_domain" {
  description = "The root domain used for email (e.g., example.com)"
  type        = string
  default     = ""
}
