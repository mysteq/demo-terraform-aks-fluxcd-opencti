
resource "azurerm_resource_group" "demo" {
  name     = "demo-aks-westeu"
  location = "westeurope"  
}

module "kubernetes" {
  source  = "amestofortytwo/aks/azurerm"
  version = "2.1.0"

  name                = "demo-aks-westeu"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location

  tags = {
    environment = "demo"
  }
}