# The identity CI acts as, and it holds no key. GitHub mints a token, the
# federation exchanges it for a short-lived credential, and nothing long-lived
# exists to leak.
resource "google_service_account" "deployer" {
  account_id   = "deployer"
  display_name = "GitHub Actions, applying this configuration"
  description  = "Federated to aleogr/shared-infra. Owns the instance, and no tenant's data."
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # WITHOUT THIS, ANY REPOSITORY ON GITHUB CAN ASK. The condition is what makes
  # the federation an authorisation rather than an introduction.
  attribute_condition = "assertion.repository == 'aleogr/shared-infra'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "deployer_federation" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.repository/aleogr/shared-infra"
}

resource "google_project_iam_member" "deployer_sql" {
  project = var.project_id
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_project_iam_member" "deployer_iam" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

data "google_project" "current" {
  project_id = var.project_id
}
