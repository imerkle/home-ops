terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.23.0"
    }
  }
}

provider "coder" {
  # Provider will be configured via CODER_URL and CODER_SESSION_TOKEN environment variables
}

resource "coder_template_version" "kubernetes_dev" {
  directory = "${path.module}/../template"
}

resource "coder_template" "kubernetes_dev" {
  name         = "kubernetes-dev"
  display_name = "Kubernetes Developer Workspace"
  description  = "A standard development environment running inside a Kubernetes Pod."

  versions {
    active_id = coder_template_version.kubernetes_dev.id
  }
}
