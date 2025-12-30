##############################################################################
# Terraform State Storage - Azure Blob Storage
##############################################################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

##############################################################################
# Local Variables
##############################################################################

locals {
  # Location for resources
  location = "southeastasia"

  # Tags
  tags = {
    Purpose     = "terraform-state"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

##############################################################################
# Random Suffix for Unique Naming
##############################################################################

resource "random_integer" "suffix" {
  min = 10
  max = 99
}

##############################################################################
# Resource Group for Terraform State
##############################################################################

resource "azurerm_resource_group" "tfstate" {
  name     = "extremelab-tfstate"
  location = local.location

  tags = local.tags
}

##############################################################################
# Storage Account for Terraform State
##############################################################################

resource "azurerm_storage_account" "tfstate" {
  name                     = "extremelabtfstate${random_integer.suffix.result}"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Enable versioning for state file protection
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

##############################################################################
# Blob Container for Terraform State
##############################################################################

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

##############################################################################
# Outputs
##############################################################################

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Name of the blob container"
  value       = azurerm_storage_container.tfstate.name
}

output "backend_config" {
  description = "Backend configuration for use in other Terraform configurations"
  value       = <<-EOT
    terraform {
      backend "azurerm" {
        resource_group_name  = "${azurerm_resource_group.tfstate.name}"
        storage_account_name = "${azurerm_storage_account.tfstate.name}"
        container_name       = "${azurerm_storage_container.tfstate.name}"
        key                  = "terraform.tfstate"
      }
    }
  EOT
}
