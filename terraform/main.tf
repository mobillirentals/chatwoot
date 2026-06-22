terraform {
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Descomente após criar o Storage Account manualmente para guardar o estado remoto.
  # backend "azurerm" {
  #   resource_group_name  = "rg-chatwoot-prod"
  #   storage_account_name = "chatwootterraformstate"
  #   container_name       = "tfstate"
  #   key                  = "chatwoot.terraform.tfstate"
  # }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

locals {
  prefix = "chatwoot"
  tags = {
    project     = "mobilli-chatwoot"
    environment = "production"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-chatwoot-prod"
  location = var.location
  tags     = local.tags
}
