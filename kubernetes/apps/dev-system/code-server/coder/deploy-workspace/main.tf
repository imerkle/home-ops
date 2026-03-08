terraform {
  required_providers {
    coderd = {
      source  = "coder/coderd"
      version = "~> 0.0.15"
    }
  }
}

provider "coderd" {
  # Provider will be configured via CODER_URL and CODER_SESSION_TOKEN environment variables
}

data "coderd_template" "kubernetes_dev" {
  name = "kubernetes-dev"
}

resource "coderd_workspace" "dev_workspace" {
  name        = "workspace"
  template_id = data.coderd_template.kubernetes_dev.id
  # Owner defaults to the authenticated user (from CODER_SESSION_TOKEN)
  # You can also pass parameter values if required by the template:
  # template_properties = {
  #   cpu    = "2"
  #   memory = "4"
  #   ...
  # }
}
