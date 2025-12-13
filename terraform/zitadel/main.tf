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

# ... (rest of the resources from the previous step) ...