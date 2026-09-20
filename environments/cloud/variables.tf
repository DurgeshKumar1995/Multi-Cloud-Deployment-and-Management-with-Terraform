variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "demo"
}

variable "name_prefix" {
  description = "Prefix for cloud resource names."
  type        = string
  default     = "multicloud"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix must start with a lowercase letter and contain 3-21 lowercase letters, numbers, or hyphens."
  }
}

variable "enable_aws" {
  description = "Create paid AWS resources."
  type        = bool
  default     = false
}

variable "enable_azure" {
  description = "Create paid Azure resources."
  type        = bool
  default     = false
}

variable "enable_gcp" {
  description = "Create paid GCP resources."
  type        = bool
  default     = false
}

variable "enable_dns" {
  description = "Create public Route 53 records and health checks. Enable only after at least two clouds are healthy."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_dns || length(compact([var.enable_aws ? "aws" : "", var.enable_azure ? "azure" : "", var.enable_gcp ? "gcp" : ""])) >= 2
    error_message = "enable_dns requires at least two enabled cloud providers."
  }
}

variable "enable_databases" {
  description = "Create billable managed PostgreSQL instances. Disabled by default."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "Public OCI image deployed to all cloud VMs. Publish it before enabling cloud resources."
  type        = string
  default     = "ghcr.io/durgeshkumar1995/multicloud-demo:v1.0.0"
}

variable "container_port" {
  description = "Port exposed by the demo container."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Unauthenticated HTTP health endpoint."
  type        = string
  default     = "/health"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "alert_email" {
  description = "Optional email for cloud monitoring alerts. Provider confirmation may be required."
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "aws_ami_id" {
  description = "Optional pinned Ubuntu AMI. Empty selects the latest official Canonical Ubuntu 24.04 AMD64 GP3 image."
  type        = string
  default     = ""

  validation {
    condition     = var.aws_ami_id == "" || can(regex("^ami-[0-9a-f]+$", var.aws_ami_id))
    error_message = "aws_ami_id must be empty or a valid AMI identifier."
  }
}

variable "aws_instance_type" {
  description = "AWS EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "azure_location" {
  description = "Azure programmatic region name."
  type        = string
  default     = "centralindia"
}

variable "azure_resource_group_name" {
  description = "Existing Azure resource group with Contributor assigned to the HCP identity."
  type        = string
  default     = "rg-multicloud-terraform"
}

variable "azure_admin_username" {
  description = "Administrator username for Azure Linux VMs."
  type        = string
  default     = "azureadmin"
}

variable "azure_ssh_public_key" {
  description = "SSH public key for Azure VMs. Required when Azure is enabled."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_azure || can(regex("^ssh-(rsa|ed25519|ecdsa)", var.azure_ssh_public_key))
    error_message = "Set azure_ssh_public_key to a valid public key before enabling Azure."
  }
}

variable "gcp_project_id" {
  description = "GCP project ID."
  type        = string
  default     = "multicloudproject-508411"
}

variable "gcp_region" {
  description = "GCP region."
  type        = string
  default     = "asia-south1"
}

variable "gcp_zones" {
  description = "Two GCP zones used by the regional managed instance group."
  type        = list(string)
  default     = ["asia-south1-a", "asia-south1-b"]

  validation {
    condition     = length(var.gcp_zones) >= 2 && alltrue([for zone in var.gcp_zones : startswith(zone, "${var.gcp_region}-")])
    error_message = "Provide at least two zones inside gcp_region."
  }
}

variable "domain_name" {
  description = "Route 53 delegated public zone."
  type        = string
  default     = "multicloud.durgesh.space"
}

variable "hosted_zone_id" {
  description = "Route 53 public hosted zone ID."
  type        = string
  default     = "Z03424422VGD13RVLRX4"
}

variable "application_hostname" {
  description = "Public application hostname within domain_name."
  type        = string
  default     = "app.multicloud.durgesh.space"
}

variable "database_admin_username" {
  description = "PostgreSQL administrator username."
  type        = string
  default     = "multicloudadmin"
}

variable "database_admin_password" {
  description = "Password for Azure/GCP PostgreSQL when databases are enabled. Store only as a sensitive HCP variable."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = !var.enable_databases || length(var.database_admin_password) >= 16
    error_message = "Set a database_admin_password of at least 16 characters before enabling databases."
  }
}
