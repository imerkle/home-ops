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
  token  = var.zitadel_token
}

# ... (rest of the resources from the previous step) ...