# `billing_project` is stated rather than inherited. Left out, the provider
# takes whatever `gcloud config set project` last wrote — which is not a
# default but a leftover, and it changes when a Cloud Shell session restarts.
# Every call would then be charged to another project's quota and refused, with
# an error naming the wrong project in its advice.
provider "google" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}
