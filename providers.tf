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
    resource_group_name  = "rg-tfstate-01"
    storage_account_name = "tfstateaks54355"
    container_name       = "tfstateaks"
    key                  = "tfstateaks.tfstate"
    subscription_id = "87e43d6c-337a-44f8-b908-c4b12dd914a9"
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
