# Backend configuration
terraform {
  backend "gcs" {
    bucket = "logscale-terraform-state-v1"
    prefix = "logscale/gcp-components/terraform/tf.state"
  }
}

# Remote Terraform data from LogScale GCP
data "terraform_remote_state" "logscale_gcp" {
  backend = "gcs"
  config = {
    bucket = var.logscale_gcp_tf_state_bucket
    prefix = "logscale/gcp/terraform/tf.state"
  }
}
 