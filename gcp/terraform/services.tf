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

  # `disable_on_destroy` alone does not keep the promise above: this
  # resource's `deletion_policy` defaults to `DELETE`, which the provider
  # documents as allowing the resource itself to be deleted — and for a
  # `google_project_service`, deleting it is disabling the service. A default
  # is a decision made somewhere else by somebody who does not know what this
  # project is, so it is stated here instead of inherited.
  deletion_policy = "ABANDON"
}
