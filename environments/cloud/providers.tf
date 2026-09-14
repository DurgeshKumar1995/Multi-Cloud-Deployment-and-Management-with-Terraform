provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

