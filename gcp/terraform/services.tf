resource "google_project_service" "enabled" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudscheduler.googleapis.com",
  ])

  service = each.value

  # Turning an API off does not remove what it created; it breaks it. A
  # `terraform destroy` that disabled sqladmin would leave an instance nobody
  # can read.
  disable_on_destroy = false
}
