locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "multicloud-terraform"
  }
}

module "aws" {
  count  = var.enable_aws ? 1 : 0
  source = "./modules/aws"

  name_prefix        = var.name_prefix
  environment        = var.environment
  region             = var.aws_region
  ami_id             = var.aws_ami_id
  instance_type      = var.aws_instance_type
  container_image    = var.container_image
  container_port     = var.container_port
  health_check_path  = var.health_check_path
  alert_email        = var.alert_email
  enable_database    = var.enable_databases
  enable_mongodb     = var.enable_aws_mongodb
  mongodb_secret_arn = var.aws_mongodb_secret_arn
  mongodb_database   = var.mongodb_database
}

module "azure" {
  count  = var.enable_azure ? 1 : 0
  source = "./modules/azure"

  name_prefix             = var.name_prefix
  environment             = var.environment
  location                = var.azure_location
  resource_group_name     = var.azure_resource_group_name
  admin_username          = var.azure_admin_username
  ssh_public_key          = var.azure_ssh_public_key
  container_image         = var.container_image
  container_port          = var.container_port
  health_check_path       = var.health_check_path
  alert_email             = var.alert_email
  enable_database         = var.enable_databases
  database_admin_username = var.database_admin_username
  database_admin_password = var.database_admin_password
}

module "gcp" {
  count  = var.enable_gcp ? 1 : 0
  source = "./modules/gcp"

  name_prefix             = var.name_prefix
  environment             = var.environment
  project_id              = var.gcp_project_id
  region                  = var.gcp_region
  zones                   = var.gcp_zones
  container_image         = var.container_image
  container_port          = var.container_port
  health_check_path       = var.health_check_path
  alert_email             = var.alert_email
  enable_database         = var.enable_databases
  database_admin_username = var.database_admin_username
  database_admin_password = var.database_admin_password
}
