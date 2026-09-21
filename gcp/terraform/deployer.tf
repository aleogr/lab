# THE REPOSITORIES THIS PROJECT TRUSTS, in the one list that says so.
#
# One name, and the check in CI asserts the live provider names exactly that.
# The list was briefly two while this repository was renamed
# (docs/superpowers/specs/2026-09-21-lab-home-design.md, D3).
locals {
  federated_repositories = [
    "aleogr/lab",
  ]
}

# The identity CI acts as, and it holds no key. GitHub mints a token, the
# federation exchanges it for a short-lived credential, and nothing long-lived
# exists to leak.
resource "google_service_account" "deployer" {
  account_id   = "deployer"
  display_name = "GitHub Actions, applying this configuration"
  description  = "Federated to aleogr/lab. Owns the instance, and no tenant's data."
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
  attribute_condition = join(" || ", [
    for repository in local.federated_repositories :
    "assertion.repository == '${repository}'"
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "deployer_federation" {
  for_each = toset(local.federated_repositories)

  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.repository/${each.value}"
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


# AND THE POOL IT AUTHENTICATES ITSELF WITH, which is the one this
# configuration declares. Neither cloudsql.admin nor projectIamAdmin can read a
# workload identity pool, so the first plan run AS this identity failed
# refreshing it — the bootstrap plan did not catch it, because that one runs as
# the project's owner.
#
# It is also granted by hand once, because the chicken and egg bites here: this
# binding cannot be applied by an identity that cannot read the pool. The
# declaration is what keeps it true afterwards.
resource "google_project_iam_member" "deployer_workload_identity" {
  project = var.project_id
  role    = "roles/iam.workloadIdentityPoolAdmin"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# AND THE CUSTOM ROLE A TENANT IS GRANTED. `projectIamAdmin` says who may hold
# a role; it holds no `iam.roles.*` permission at all, so it cannot create the
# role itself. This one is granted by hand once for the same reason as the
# binding above: applying it and then using it in the same run races the few
# minutes IAM takes to propagate.
resource "google_project_iam_member" "deployer_roles" {
  project = var.project_id
  role    = "roles/iam.roleAdmin"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}
data "google_project" "current" {
  project_id = var.project_id
}
