/* WHEN THE INSTANCE IS AWAKE — the schedule itself, and one of the two
   places the expressions live on purpose, not the only one.

   THE OTHER IS `.github/workflows/ci.yml`'s `check-schedule.sh` invocation,
   which passes these same two cron strings back as what that script is told
   to expect. That is not drift, it is deliberate: a check must not read its
   expectation from the thing it is checking (`check-federation.sh` is the
   pattern), so `check-schedule.sh` cannot read its expectation out of this
   file — it would then agree with whatever this file said, always.
   CHANGING THE WINDOW MEANS CHANGING BOTH, this file and the arguments in
   `ci.yml`. `docs/lab.md` names both places rather than claiming either is
   the only one.

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

  # THE SECOND DEPENDENCY IS NOT IMPLIED BY THE `oauth_token` REFERENCE
  # ABOVE. Referencing `google_service_account.sleeper.email` only tells
  # Terraform this job needs the account to exist first; it says nothing
  # about `deployer_acts_as_sleeper` (`sleeper.tf`), the binding that lets
  # `deployer@` — the identity running this apply — create a job that acts
  # as `sleeper@` in the first place. Nothing else in this resource touches
  # that binding, so without stating it here the graph could create this job
  # before the binding exists, and the create call would fail exactly the
  # way it already has once.
  depends_on = [
    google_project_service.enabled,
    google_service_account_iam_member.deployer_acts_as_sleeper,
  ]
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

  # Same reason as the stop job above: the `oauth_token` reference implies
  # only that `sleeper@` must exist first, not that `deployer_acts_as_sleeper`
  # (`sleeper.tf`) must exist before `deployer@` can create a job that acts
  # as it.
  depends_on = [
    google_project_service.enabled,
    google_service_account_iam_member.deployer_acts_as_sleeper,
  ]
}
