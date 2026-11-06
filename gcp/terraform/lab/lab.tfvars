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

  iam = {
    # Applied by aleogr/iam's CI from main, through that project's own
    # federation (aleogr/iam: deploy/gcp/terraform).
    declares = "iam-deployer@aleogr-lab-iam-c4vc.iam.gserviceaccount.com"
    connects = [
      "iam-run@aleogr-lab-iam-c4vc.iam.gserviceaccount.com",
      "iam-migrate@aleogr-lab-iam-c4vc.iam.gserviceaccount.com",
    ]
    # The service logs in as an IAM database user; the migration job uses
    # the password user iam_migrator, so it is not here.
    logs_in = [
      "iam-run@aleogr-lab-iam-c4vc.iam.gserviceaccount.com",
    ]
    # The release reads `activationPolicy` before it starts. The planner reads
    # the tenant's own database and users when aleogr/iam's pull requests
    # plan; it holds no write and opens no connection.
    reads = [
      "iam-release@aleogr-lab-iam-c4vc.iam.gserviceaccount.com",
      "iam-planner@aleogr-lab-iam-c4vc.iam.gserviceaccount.com",
    ]
  }
}
