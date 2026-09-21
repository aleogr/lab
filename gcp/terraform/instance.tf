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

    # `activation_policy` IS ABSENT ON PURPOSE. It is the one setting this
    # file does not own: `sleep.tf` changes it four times a week, and CI
    # applies this configuration on every merge to main. A line here naming
    # ALWAYS would wake the instance whenever somebody shipped a
    # documentation fix, and the schedule would lose to Terraform every time.
    # Completing this block by adding it would silently disable the schedule.

    disk_type             = "PD_SSD"
    disk_size             = var.database_disk_size
    disk_autoresize       = true
    disk_autoresize_limit = var.database_disk_limit

    backup_configuration {
      enabled = true

      # NOON UTC, AND THE HOUR IS THE WHOLE POINT. A stopped instance runs no
      # automated backup, and Plan 2 will stop this instance from 22:00 to
      # 07:30 local on Monday, Tuesday, Wednesday and Thursday nights. A
      # backup window in the small hours would mean both projects quietly
      # stopped having daily backups — no error, nothing to notice, just an
      # absence.
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

  depends_on = [google_project_service.enabled]
}
