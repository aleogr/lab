# lab/lab.tfvars — project_id arrives from the repository variable GCP_PROJECT_ID
region = "us-central1"

tenants = {
  schooling = {
    # No `declares`: schooling's Terraform is applied by the owner from Cloud
    # Shell, not by a service account, and the owner already holds more than
    # `sqlTenant` here.
    connects = [
      "schooling-run@aleogr-schooling.iam.gserviceaccount.com",
    ]
    # The release reads `activationPolicy` before it pushes anything.
    reads = [
      "schooling-deploy@aleogr-schooling.iam.gserviceaccount.com",
    ]
    # A password user, not an IAM one.
    logs_in = []
  }
}
