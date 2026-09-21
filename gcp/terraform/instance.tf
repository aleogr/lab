/* The instance both labs share, and the only thing this repository owns.

   IT DOES NOT SCALE TO ZERO, which is why it sleeps instead. Cloud Run costs
   nothing while nobody is reading; this is charged by the hour whether or not
   anybody is, and it is the whole standing cost of both projects. The schedule
   that stops it on weeknights is `sleep.tf`.

   THE EDITION IS SAID OUT LOUD. Left out, the API picks ENTERPRISE_PLUS, where
   shared-core tiers do not exist at all, and refuses `db-f1-micro` with a
   message suggesting a machine several times this bill. The tier and the
   edition are one decision, and the API will make the half nobody wrote down.

   NOTHING HERE NAMES A TENANT. A database, a role or a grant in this file
   would make this repository the owner of somebody else's data. They are
   declared by their tenants, against this instance. */
resource "google_sql_database_instance" "shared" {
  name             = "lab-postgres"
  database_version = "POSTGRES_16"
  region           = var.region

  deletion_protection = true

  settings {
    edition           = "ENTERPRISE"
    tier              = var.database_tier
    availability_type = "ZONAL"

    deletion_protection_enabled = true

    disk_type             = "PD_SSD"
    disk_size             = var.database_disk_size
    disk_autoresize       = true
    disk_autoresize_limit = var.database_disk_limit

    backup_configuration {
      enabled = true

      # NOON UTC, AND THE HOUR IS THE WHOLE POINT. A stopped instance runs no
      # automated backup, and `sleep.tf`, two files over, stops this instance
      # from 22:00 to 07:30 local on Monday, Tuesday, Wednesday and Thursday
      # nights. A backup window in the small hours would mean both projects
      # quietly stopped having daily backups — no error, nothing to notice,
      # just an absence.
      start_time = "12:00"

      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      # A public address with NO authorized networks, which is not the
      # contradiction it reads as: with an empty list nothing on the internet
      # can open a connection. The way in is the Cloud SQL connector, which
      # authenticates with IAM and encrypts per connection.
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }

    database_flags {
      # The marketplace service authenticates with a token instead of a
      # password. Password users are unaffected, so `schooling` keeps working
      # exactly as it does today.
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }

  # `activation_policy` IS IGNORED, NOT ABSENT, and this block is the second
  # attempt. `sleep.tf` owns this field and nothing else does.
  #
  # THE FIRST ATTEMPT WAS TO LEAVE THE LINE OUT OF `settings`, on the theory
  # that an unset field is an unmanaged one. It is not. Unlike `edition` and
  # `disk_type` above, `activation_policy` is Optional but not Computed in
  # the provider's own schema — checked directly with
  # `terraform providers schema -json` against provider 8.3.0 — and the
  # provider fills an absent value in with ALWAYS rather than leaving it
  # alone. A plan run against a state whose `activation_policy` was `NEVER`
  # — the instance stopped for the night, reproduced by hand against the
  # same provider — proposed `NEVER -> ALWAYS`, in place, every time.
  #
  # WHAT THAT WOULD HAVE COST: CI applies this configuration on every merge
  # to main. A documentation fix merged at 23:00 on a Tuesday would have
  # woken the instance back up, and `check-instance.sh` would have passed
  # immediately afterwards, because it does not read this field. The
  # schedule would have lost to Terraform in silence, four nights a week,
  # and nothing here would have said so.
  #
  # THE TRADE THIS ACCEPTS: with `ignore_changes`, Terraform never manages
  # this field again, in either direction. An instance stopped by hand and
  # forgotten stays stopped; no apply will wake it back up on its own. That
  # is deliberate, not an oversight — the schedule in `sleep.tf` is what
  # decides whether the instance is awake, and `check-schedule.sh` is what
  # verifies the schedule matches the design. This block does not verify
  # anything, and is not meant to.
  lifecycle {
    ignore_changes = [settings[0].activation_policy]
  }

  depends_on = [google_project_service.enabled]
}
