
resource "azurerm_resource_group" "demo" {
  name     = "demo-aks-westeu"
  location = "westeurope"
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "demo" {
  location            = azurerm_resource_group.demo.location
  name                = "demo-aks-ui-westeu"
  resource_group_name = azurerm_resource_group.demo.name
}

resource "azurerm_key_vault" "demo" {
  name                        = "demo-aks-westeu"
  location                    = azurerm_resource_group.demo.location
  resource_group_name         = azurerm_resource_group.demo.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover"
    ]

    storage_permissions = [
      "Get",
    ]
  }

  access_policy {
    tenant_id = azurerm_user_assigned_identity.demo.tenant_id
    object_id = azurerm_user_assigned_identity.demo.principal_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}

resource "azurerm_key_vault_secret" "demo" {
  name         = "aks-sops-key"
  value        = "szechuan"
  key_vault_id = azurerm_key_vault.demo.id
}

module "kubernetes" {
  source  = "amestofortytwo/aks/azurerm"
  version = "2.1.0"

  name                = "demo-aks-westeu"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location

  workload_identity_enabled = true

  tags = {
    environment = "demo"
  }
}

data "azurerm_kubernetes_cluster" "demo" {
  name                = "demo-aks-westeu"
  resource_group_name = azurerm_resource_group.demo.name

  depends_on = [
    module.kubernetes
  ]
}

resource "azurerm_role_assignment" "example" {
  scope                = data.azurerm_kubernetes_cluster.demo.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = "71edc320-9813-45bb-af1e-2e6eff6fa4d5"
}

resource "azurerm_federated_identity_credential" "demo" {
  name                = "demo-aks-westeu"
  resource_group_name = azurerm_resource_group.demo.name
  issuer              = data.azurerm_kubernetes_cluster.demo.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:flux-system:sops"
}

