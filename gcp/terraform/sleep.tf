/* WHEN THE INSTANCE IS AWAKE, and the only place the expressions live.

   Cloud Scheduler calls the Cloud SQL Admin API itself. The alternative
   everybody reaches for — Scheduler to Pub/Sub to a Cloud Function — buys a
   runtime, a deployment and a piece of source to maintain, all to issue one
   HTTP request that Scheduler can issue on its own.

   NOT A SCHEDULED GITHUB ACTIONS WORKFLOW, for two reasons that are each
   enough. It would put a cron in the repository that holds a federation able
   to change a GCP project, and GitHub delays scheduled runs under load — an
   instance that sleeps at 22:14 because a queue was busy is not a schedule.

   The window is four weeknights: Friday night and Sunday night are left awake
   deliberately. The reasoning is in the 2026-09-20 design, and `docs/lab.md`
   states the policy for a reader who is not reading Terraform. */

resource "google_cloud_scheduler_job" "stop" {
  project     = var.project_id
  region      = var.region
  name        = "lab-postgres-stop"
  description = "Stops the shared instance for the night."

  schedule  = "0 22 * * 1-4"
  time_zone = "America/Sao_Paulo"

  attempt_deadline = "320s"

  # A stop that fails costs a few reais of instance-hours and nothing else.
  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "PATCH"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${google_sql_database_instance.shared.name}"
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode(jsonencode({ settings = { activationPolicy = "NEVER" } }))

    oauth_token {
      service_account_email = google_service_account.sleeper.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_project_service.enabled]
}

resource "google_cloud_scheduler_job" "start" {
  project     = var.project_id
  region      = var.region
  name        = "lab-postgres-start"
  description = "Starts the shared instance before the working day."

  schedule  = "30 7 * * 2-5"
  time_zone = "America/Sao_Paulo"

  attempt_deadline = "320s"

  # A START THAT FAILS IS NOT LIKE A STOP THAT FAILS. A day that begins against
  # a dead database is the failure this schedule can actually cause, so this
  # one retries and the stop does not.
  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "PATCH"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${google_sql_database_instance.shared.name}"
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode(jsonencode({ settings = { activationPolicy = "ALWAYS" } }))

    oauth_token {
      service_account_email = google_service_account.sleeper.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_project_service.enabled]
}
