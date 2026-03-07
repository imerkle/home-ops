terraform {
  required_providers {
    coderd = {
      source  = "coder/coderd"
      version = "~> 1.0"
    }
  }
}

provider "coderd" {
  # Provider will be configured via CODER_URL and CODER_SESSION_TOKEN environment variables
}

resource "coderd_template" "kubernetes_dev" {
  name        = "kubernetes-dev"
  description = "A standard development environment running inside a Kubernetes Pod."

  versions = [
    {
      directory = "${path.module}/../template"
    }
  ]
}
