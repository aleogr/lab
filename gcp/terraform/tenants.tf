/* WHAT A TENANT MAY DO INSIDE THIS INSTANCE, and nothing beyond it.

   The role is the one written out in tenant_role.tf: it declares the tenant's
   own database and its own users, and it cannot delete the instance or change
   its settings, which is the boundary this repository exists to hold.

   THE CONNECT AND LOGIN GRANTS ARE HERE AND NOT IN THE TENANT because both are
   checked against the project that OWNS the instance. A tenant granting them
   to itself would need `projectIamAdmin` on this project — the right to give
   anything to anyone here — which is a larger power than the one it is asking
   for. So the house says who may come in. */

resource "google_project_iam_member" "tenant_deployers" {
  for_each = var.tenants

  project = var.project_id
  role    = google_project_iam_custom_role.tenant.name
  member  = "serviceAccount:${each.value.declares}"
}

# `cloudsql.client` opens a connection through the connector.
resource "google_project_iam_member" "tenant_connects" {
  for_each = toset(flatten([for tenant in var.tenants : tenant.connects]))

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${each.value}"
}

# `cloudsql.instanceUser` is what makes an IAM database user able to log in at
# all. Only the identities that hold no password need it.
resource "google_project_iam_member" "tenant_logs_in" {
  for_each = toset(flatten([for tenant in var.tenants : tenant.logs_in]))

  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = "serviceAccount:${each.value}"
}
