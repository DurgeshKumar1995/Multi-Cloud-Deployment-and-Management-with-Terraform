output "public_ip" {
  value = google_compute_global_address.application.address
}

output "endpoint_url" {
  value = "http://${google_compute_global_address.application.address}"
}

output "storage_bucket" {
  value = google_storage_bucket.backup.name
}

output "database_connection_name" {
  value     = try(google_sql_database_instance.database[0].connection_name, null)
  sensitive = true
}
