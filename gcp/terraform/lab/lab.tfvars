# lab/lab.tfvars — project_id arrives from the repository variable GCP_PROJECT_ID
region = "us-central1"

tenants = {
  marketplace = {
    deployer = "deployer@aleogr-marketplace-lab-a4j5.iam.gserviceaccount.com"
    connects = [
      "marketplace-run@aleogr-marketplace-lab-a4j5.iam.gserviceaccount.com",
      "marketplace-migrate@aleogr-marketplace-lab-a4j5.iam.gserviceaccount.com",
    ]
    logs_in = [
      "marketplace-run@aleogr-marketplace-lab-a4j5.iam.gserviceaccount.com",
    ]
  }
}
