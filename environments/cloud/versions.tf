terraform {
  required_version = ">= 1.8.0"

  cloud {
    organization = "Multi-Cloud-Deployment-and-Management"

    workspaces {
      name = "Multi-Cloud-Deployment_Management_Terraform"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
