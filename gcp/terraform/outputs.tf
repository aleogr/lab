output "connection_name" {
  description = "How a tenant addresses this instance: <project>:<region>:<instance>. It is what Cloud Run mounts and what the connector dials."
  value       = google_sql_database_instance.shared.connection_name
}

output "instance_name" {
  description = "The instance's own name, for a tenant declaring a database inside it."
  value       = google_sql_database_instance.shared.name
}
