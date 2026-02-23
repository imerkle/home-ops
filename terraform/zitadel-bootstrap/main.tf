terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "2.7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}
provider "kubernetes" {
  # config_path = "~/.kube/config"
  # Configuration depends on your environment (e.g., config_path = "~/.kube/config")
}


# --- INPUT VARIABLES ---
variable "zitadel_domain" {
  type    = string
  default = "zitadel.x3y.space"
}


data "kubernetes_secret_v1" "zitadel_iam_admin" {
  metadata {
    name      = "iam-admin"
    namespace = "zitadel"
  }
}

# --- PROVIDER ---
provider "zitadel" {
  domain = var.zitadel_domain
  # Ensure this file exists in this folder, or pass content via env var
  # jwt_profile_file = "jwt.json"
  jwt_profile_json = data.kubernetes_secret_v1.zitadel_iam_admin.data["iam-admin.json"]
}

# --- RESOURCES ---
resource "random_pet" "org_name" {
  length    = 2
  separator = "-"
}

resource "random_pet" "project_name" {
  length    = 2
  separator = "-"
}

# Create the organization
resource "zitadel_organization" "org" {
  name = random_pet.org_name.id
}

# Create project within the organization
resource "zitadel_project" "project" {
  name   = random_pet.project_name.id
  org_id = zitadel_organization.org.id

  project_role_assertion = true
  has_project_check      = false
}

# --- OUTPUTS ---
output "org_id" {
  value = zitadel_organization.org.id
}

output "project_id" {
  value = zitadel_project.project.id
}
