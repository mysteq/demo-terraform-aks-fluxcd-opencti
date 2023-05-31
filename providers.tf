terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.56.0"
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
  subscription_id = "ad3a592d-2f32-4013-8b6a-a290a0aafed2"
}

provider "azurerm" {
  features {}
  alias           = "dns"
  subscription_id = "646dcda3-7645-475b-8dc3-be6257586e68"
}
