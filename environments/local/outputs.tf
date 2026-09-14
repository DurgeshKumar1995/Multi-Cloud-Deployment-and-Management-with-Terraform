output "floci_endpoint" {
  description = "Local AWS-compatible Floci endpoint."
  value       = "http://localhost:14566"
}

output "bucket_name" {
  description = "Bucket created in the local Floci emulator."
  value       = aws_s3_bucket.demo.id
}
