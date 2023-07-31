terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.63.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.1"
    }
  }
  backend "azurerm" {
    resource_group_name  = "tfstatedemoaks"
    storage_account_name = "tfstateaks54355"
    container_name       = "tfstateaks"
    key                  = "tfstateaks.tfstate"
    subscription_id = "ad3a592d-2f32-4013-8b6a-a290a0aafed2"
  }
}

provider "azurerm" {
  features {     
    resource_group {
       prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = "e5183437-65de-4900-9987-9b9ff0fae0a3"
}
