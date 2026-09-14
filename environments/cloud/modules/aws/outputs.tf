output "endpoint_hostname" {
  value = aws_lb.application.dns_name
}

output "endpoint_url" {
  value = "http://${aws_lb.application.dns_name}"
}

output "backup_bucket" {
  value = aws_s3_bucket.backup.id
}

output "database_endpoint" {
  value     = try(aws_db_instance.database[0].endpoint, null)
  sensitive = true
}
