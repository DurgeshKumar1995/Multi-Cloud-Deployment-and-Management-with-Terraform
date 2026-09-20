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

output "application_public_ips" {
  description = "Stable public egress IPs to add to the MongoDB Atlas IP access list when MongoDB is enabled."
  value       = var.enable_mongodb ? aws_eip.application[*].public_ip : []
}
