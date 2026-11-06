# The bucket cannot be created by the configuration that needs it, so it was
# made by hand and is recorded in README.md, "What was done by hand".
# Its name reaches CI as the repository variable TF_STATE_BUCKET; the prefix
# comes from lab/backend.hcl. Both arrive through -backend-config.
terraform {
  backend "gcs" {}
}
