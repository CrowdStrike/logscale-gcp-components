# Variable definitions
# These varriables can be overriden with the _override.tf file or by specifying then on the command line
# using -var
# Many of these varibales are undefined and interpolated in the Terraform files

# GCP Project ID
variable "project_id" {
  default = ""
}

# Public URL of the cluster
variable "public_url" {
  type    = string
  default = ""
}

# Remote state where the LogScale GCP Terraform state is stored
variable "logscale_gcp_tf_state_bucket" {
  type    = string
  default = "logscale-terraform-state-v1"
}


# Issue client certificate
variable "issue_client_certificate" {
  default = false
}

# Strimzi operator chart version
variable "strimzi_operator_chart_version" {
  type    = string
  default = "0.37.0"
}

# Kubernetes namespace for the LogScale cluster
variable "logscale_cluster_k8s_namespace_name" {
  default = "logging"
  type    = string
}


# Cert-manager CRD URL
variable "cm_crds_url" {
  type    = string
  default = "https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.crds.yaml"
}

# Cert-manager repo
variable "cm_repo" {
  type    = string
  default = "https://charts.jetstack.io"
}

# Cert-manager namespace
variable "cm_namespace" {
  type    = string
  default = "cert-manager"
}

# Cert-manager version
variable "cm_version" {
  type    = string
  default = "v1.13.1"
}

# Cert-manager issuer name
variable "issuer_name" {
  type    = string
  default = "letsencrypt-cluster-issuer"
}

# Cert-manager issuer kind
variable "issuer_kind" {
  type    = string
  default = "ClusterIssuer"
}

# Cert-manager issuer email
variable "issuer_email" {
  type    = string
  default = "logscale-gke@humio.com"
}

# Cert-manager issuer private key
variable "issuer_private_key" {
  type    = string
  default = "letsencrypt-cluster-issuer-key"
}

# Cert-manager CA server
variable "ca_server" {
  type    = string
  default = "https://acme-v02.api.letsencrypt.org/directory"
}


# Humio Operator version
variable "humio_operator_version" {
  type    = string
  default = "0.20.0"
}

# Enable the Humio operator
variable "humio_operator_enabled" {
  type    = string
  default = "true"
}

# Humio helm chart version
variable "humio_helm_chart_version" {
  type    = string
  default = "0.9.5"
}

# Humio operator chart version
variable "humio_operator_chart_version" {
  type    = string
  default = "0.20.0"
}

# Humio operator resource definitions
variable "humio_operator_extra_values" {
  type = map(string)
  default = {
    "operator.resources.limits.cpu"      = "250m"
    "operator.resources.limits.memory"   = "750Mi"
    "operator.resources.requests.cpu"    = "250m"
    "operator.resources.requests.memory" = "750Mi"
  }
}

# Humio cluster license
variable "humiocluster_license" {
  type = string
}

# LogScale cluster type
variable "logscale_cluster_type" {
  default = "basic"
  type    = string
  validation {
    condition     = contains(["basic", "ingress", "internal-ingest"], var.logscale_cluster_type)
    error_message = "logscale_cluster_type must be one of: basic, advanced, or internal-ingest"
  }
}

# LogScale cluster size
variable "logscale_cluster_size" {
  default = "xsmall"
  type    = string
  validation {
    condition     = contains(["xsmall", "small", "medium", "large", "xlarge"], var.logscale_cluster_size)
    error_message = "logscale_cluster_size must be one of: xsmall, small, medium, large, or xlarge"
  }
}

# Local variables from the remote Terraform state
locals {
  gke_context                  = "gke_${var.project_id}_${local.logscale_cluster_region}_${local.logscale_cluster_name}-gke"
  logscale_bucket_storage      = data.terraform_remote_state.logscale_gcp.outputs.logscale_bucket_storage
  logscale_cluster_name        = data.terraform_remote_state.logscale_gcp.outputs.logscale_cluster_name
  logscale_cluster_size        = data.terraform_remote_state.logscale_gcp.outputs.logscale_cluster_size
  logscale_cluster_type        = data.terraform_remote_state.logscale_gcp.outputs.logscale_cluster_type
  logscale_cluster_identifier  = data.terraform_remote_state.logscale_gcp.outputs.logscale_cluster_identifier
  logscale_cluster_definitions = data.terraform_remote_state.logscale_gcp.outputs.logscale_cluster_definitions
  logscale_gce_ingress_ip      = data.terraform_remote_state.logscale_gcp.outputs.logscale_gce_ingress_ip
  logscale_cluster_region      = data.terraform_remote_state.logscale_gcp.outputs.logscale_cluster_region
  logscale_cluster_zone        = data.terraform_remote_state.logscale_gcp.outputs.logscale_cluster_zone
}
