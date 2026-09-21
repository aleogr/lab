/* THE IDENTITY THAT PUTS THE INSTANCE TO SLEEP, and the role that says what
   it may do while it does.

   It is held by the two Cloud Scheduler jobs in `sleep.tf` and by nothing
   else. Both send a constant, hard-coded body to one instance's URL, so what
   this account could be made to do is exactly what those two jobs already
   do.

   THIS ROLE READS SMALLER THAN IT IS, and that is written down rather than
   left for a reader to discover. Cloud SQL has no permission that means "may
   start and stop": starting or stopping an instance is a PATCH to its
   settings, authorized by `cloudsql.instances.update` — the same permission
   that resizes the disk, rewrites the backup schedule and turns deletion
   protection off. This is the smallest role GCP offers for the job, and it
   is still larger than the job. A boundary described as tighter than it is
   gets trusted for something it does not do, so it is not described that
   way here.

   NO `databases.*` and no `users.*`: this identity reaches no tenant's data.
   NO `delete`: it cannot remove the instance it starts and stops. */
resource "google_project_iam_custom_role" "sleeper" {
  project     = var.project_id
  role_id     = "sqlSleeper"
  title       = "Cloud SQL sleeper"
  description = "Starts and stops the shared instance via cloudsql.instances.update, GCP's smallest permission for the job, which can also resize its disk, rewrite its backup schedule and turn off deletion protection. Cannot delete it and reaches no tenant's data."

  permissions = [
    "cloudsql.instances.get",
    "cloudsql.instances.update",
  ]
}

resource "google_service_account" "sleeper" {
  project      = var.project_id
  account_id   = "sleeper"
  display_name = "The schedule that stops and starts lab-postgres"
  description  = "Held by two Cloud Scheduler jobs and by nothing else. It may start and stop the shared instance; it reaches no database and no tenant."
}

resource "google_project_iam_member" "sleeper" {
  project = var.project_id
  role    = google_project_iam_custom_role.sleeper.name
  member  = "serviceAccount:${google_service_account.sleeper.email}"
}

# THE JOBS IN `sleep.tf` RUN AS `sleeper@`, NOT AS `deployer@`. Each carries
# an `oauth_token` naming `sleeper@`'s email, so creating one means creating
# something that impersonates that account — and impersonation is its own
# permission, billed and checked separately from administering the account
# being impersonated. Without this binding, `deployer@` can create the
# service account and the role above and still be refused when it tries to
# create a job that acts as either.
#
# THAT IS NOT WHAT `serviceAccountAdmin` GRANTS. `deployer.tf`'s
# `deployer_service_accounts` binding lets `deployer@` create, delete and
# otherwise manage the *identity* `sleeper@` — it says nothing about acting
# *as* it. `roles/iam.serviceAccountUser` is the permission that borrows an
# identity rather than administers one, and GCP keeps the two separate on
# purpose: holding the first does not imply the second. This was found
# exactly that way — the apply got past creating `sleeper@` and its role,
# then failed on the two Cloud Scheduler jobs with `iam.serviceAccounts.actAs`
# denied, a second missing permission behind the first.
#
# DECLARED HERE, NOT GRANTED BY HAND, unlike the project-level roles in
# `deployer.tf`. Those are granted by hand because applying them and using
# them in the same run would race IAM propagation — Terraform cannot grant
# itself a permission it needs in order to run. This binding does not have
# that problem: it targets a service account this configuration itself
# creates, so there is no chicken-and-egg. Terraform creates `sleeper@`,
# then this binding, then the two jobs that need it — an order `sleep.tf`
# states explicitly rather than leaves to the graph, since neither job
# resource references this binding to imply it.
#
# THE PATTERN IS NOT NEW. `aleogr/marketplace`'s `infra/terraform/tasks.tf`
# grants its own Cloud Tasks invoker the identical binding, for the identical
# reason its own comment gives: "Creating a task that runs as the invoker
# means acting as it."
resource "google_service_account_iam_member" "deployer_acts_as_sleeper" {
  service_account_id = google_service_account.sleeper.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
