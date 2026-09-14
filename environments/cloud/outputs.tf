output "aws_endpoint" {
  description = "AWS ALB endpoint when AWS is enabled."
  value       = try(module.aws[0].endpoint_url, null)
}

output "azure_endpoint" {
  description = "Azure load balancer endpoint when Azure is enabled."
  value       = try(module.azure[0].endpoint_url, null)
}

output "gcp_endpoint" {
  description = "GCP load balancer endpoint when GCP is enabled."
  value       = try(module.gcp[0].endpoint_url, null)
}

output "global_endpoint" {
  description = "Route 53 multi-cloud endpoint when DNS is enabled."
  value       = var.enable_dns ? "http://${var.application_hostname}" : null
}

output "deployment_safety" {
  description = "Summary of cost-bearing deployment switches."
  value = {
    aws       = var.enable_aws
    azure     = var.enable_azure
    gcp       = var.enable_gcp
    dns       = var.enable_dns
    databases = var.enable_databases
  }
}

