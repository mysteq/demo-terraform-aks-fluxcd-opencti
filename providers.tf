terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.56.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
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
  features {}
  subscription_id = "49a743cb-1b0b-4bbd-9986-f9fcf513526f"
}
