# Backend configuration
terraform {
  backend "gcs" {
    bucket = "test-new-logscale-terraform-state-v1"
    prefix = "logscale/gcp-components/terraform/tf.state"
  }
}

# Remote Terraform data from LogScale GCP
data "terraform_remote_state" "logscale_gcp" {
  backend = "gcs"
  config = {
    bucket = "test-new-logscale-terraform-state-v1"
    prefix = "logscale/gcp/terraform/tf.state"
  }
}
 