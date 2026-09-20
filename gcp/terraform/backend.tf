# The bucket cannot be created by the configuration that needs it, so it is
# made by hand and recorded in docs/infrastructure.md of aleogr/marketplace.
# Its name reaches CI as the repository variable TF_STATE_BUCKET; the prefix
# comes from lab/backend.hcl. Both arrive through -backend-config.
terraform {
  backend "gcs" {}
}
