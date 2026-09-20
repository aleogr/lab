/* NO PREDEFINED ROLE FITS A TENANT, so this one is written out.

   `roles/cloudsql.editor` creates a database but cannot create a user: it holds
   `cloudsql.users.get` and `cloudsql.users.list` and nothing that writes, so a
   tenant declaring its own users is refused with a 403 the message calls
   `notAuthorized`. `roles/cloudsql.admin` creates users and also deletes
   instances and rewrites their settings — the boundary this repository exists
   to hold. Between the two there is nothing, so the permissions are named.

   WHAT IS ABSENT IS THE POINT. No `cloudsql.instances.delete` and no
   `cloudsql.instances.update`: a tenant cannot remove the instance, resize its
   disk, change its backup schedule or stop it. No `cloudsql.databases.delete`
   either, because a tenant's database is declared with deletion_policy ABANDON
   and Terraform never asks to delete one.

   `cloudsql.users.delete` is present, because a tenant's users are declared
   with deletion_policy DELETE and renaming one is a delete followed by a
   create. It is also why this role is not a wall between tenants: Cloud SQL
   grants IAM per project, not per database, so a tenant that may delete its own
   users may delete another tenant's. That is the trade the design already
   recorded for a shared laboratory instance, and it is written here so the next
   reader does not mistake this role for isolation it does not provide. */
resource "google_project_iam_custom_role" "tenant" {
  project     = var.project_id
  role_id     = "sqlTenant"
  title       = "Cloud SQL tenant"
  description = "Declares its own database and users on the shared instance, and cannot change or delete the instance."

  permissions = [
    "cloudsql.databases.create",
    "cloudsql.databases.get",
    "cloudsql.databases.list",
    "cloudsql.databases.update",
    "cloudsql.instances.get",
    "cloudsql.instances.list",
    "cloudsql.users.create",
    "cloudsql.users.delete",
    "cloudsql.users.get",
    "cloudsql.users.list",
    "cloudsql.users.update",
  ]
}
