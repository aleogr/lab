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
  description = "Starts and stops the shared instance on a schedule. It cannot delete it and reaches no tenant's data."

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
