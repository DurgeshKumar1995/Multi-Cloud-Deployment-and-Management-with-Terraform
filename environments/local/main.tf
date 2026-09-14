resource "aws_s3_bucket" "demo" {
  bucket        = "multicloud-local-demo"
  force_destroy = true

  tags = {
    Environment = "local"
    ManagedBy   = "Terraform"
    Project     = "multicloud-terraform"
  }
}

resource "aws_s3_object" "health_marker" {
  bucket       = aws_s3_bucket.demo.id
  key          = "health/status.json"
  content      = jsonencode({ status = "healthy", environment = "local" })
  content_type = "application/json"
}

