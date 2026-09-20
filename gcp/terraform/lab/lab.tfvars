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
}
