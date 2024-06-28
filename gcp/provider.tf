# Terraform providers
provider "google" {
  project = var.project_id
  region  = local.logscale_cluster_region
}

provider "google-beta" {
  project = var.project_id
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = local.gke_context
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = local.gke_context
}

provider "null" {}

