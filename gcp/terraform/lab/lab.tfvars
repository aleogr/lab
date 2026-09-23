# lab/lab.tfvars — project_id arrives from the repository variable GCP_PROJECT_ID
region = "us-central1"

tenants = {
  marketplace = {
    # The identity CI applies the marketplace's Terraform as, which is not
    # `deployer@` — that one pushes images and deploys Cloud Run and never
    # touches Cloud SQL.
    declares = "terraform@aleogr-marketplace-lab-a4j5.iam.gserviceaccount.com"
    connects = [
      "marketplace-run@aleogr-marketplace-lab-a4j5.iam.gserviceaccount.com",
      "marketplace-migrate@aleogr-marketplace-lab-a4j5.iam.gserviceaccount.com",
    ]
    logs_in = [
      "marketplace-run@aleogr-marketplace-lab-a4j5.iam.gserviceaccount.com",
    ]
  }
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
