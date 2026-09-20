# What a tenant may do inside this instance: declare its own database and its
# own users, and nothing else. `cloudsql.editor` cannot delete the instance and
# cannot change its settings, which is the boundary this repository exists to
# hold.
resource "google_project_iam_member" "tenants" {
  for_each = var.tenants

  project = var.project_id
  role    = "roles/cloudsql.editor"
  member  = "serviceAccount:${each.value}"
}
