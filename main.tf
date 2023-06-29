
resource "azurerm_resource_group" "demo" {
  name     = "demo-aks-westeu"
  location = "westeurope"
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "demo" {
  location            = azurerm_resource_group.demo.location
  name                = "demo-aks-ui-westeu"
  resource_group_name = azurerm_resource_group.demo.name

  provisioner "local-exec" {
    command = "sed -i '' -r 's/client-id: (.*)/client-id: ${azurerm_user_assigned_identity.demo.client_id}/g' cluster/demo-euwest/flux-system/kustomization.yaml"
  }

  provisioner "local-exec" {
    command = "sed -i '' -r 's/clientId: (.*)/clientId: ${azurerm_user_assigned_identity.demo.client_id}/g' cluster/demo-euwest/flux-system/secret.yaml"
  }

}

resource "random_id" "id" {
	  byte_length = 2
}

resource "azurerm_key_vault" "demo" {
  name                        = "demo-aks-westeu-${lower(random_id.id.hex)}"
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
      "Delete",
      "Get",
      "Purge",
      "Recover",
      "Update",
      "GetRotationPolicy",
      "SetRotationPolicy",
      "Encrypt",
      "Decrypt",
      "List"
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover",
      "List"
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
      "Decrypt",
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}

resource "azurerm_key_vault_key" "demo" {
  name         = "sops-key"
  key_vault_id = azurerm_key_vault.demo.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }

  provisioner "local-exec" {
    command = "sed -i '' -r 's/azure_keyvault: (.*)/azure_keyvault: ${replace(azurerm_key_vault.demo.vault_uri,"/\\//", "\\/")}keys\\/${azurerm_key_vault_key.demo.name}\\/${azurerm_key_vault_key.demo.version}/g' .sops.yaml"
  }

  provisioner "local-exec" {
    command = "sops -e --in-place infra/elasticsearch/secret.yaml"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "sops -d --in-place infra/elasticsearch/secret.yaml"
  }

}

module "kubernetes" {
#  source  = "amestofortytwo/aks/azurerm"
#  version = "2.1.0"
  source  = "../terraform-azurerm-aks"

  name                = "demo-aks-westeu"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location

  workload_identity_enabled = true

  default_node_pool = {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_B8ms"
  }

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

resource "null_resource" "demo" {
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.demo.name} --name ${data.azurerm_kubernetes_cluster.demo.name} --overwrite-existing --subscription ${data.azurerm_client_config.current.subscription_id}"
  }
}

resource "azurerm_role_assignment" "example" {
  scope                = data.azurerm_kubernetes_cluster.demo.id
  #scope                = module.kubernetes.aks_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = "${data.azurerm_client_config.current.object_id}"
}

resource "azurerm_federated_identity_credential" "demo" {
  name                = "demo-aks-westeu"
  resource_group_name = azurerm_resource_group.demo.name
  issuer              = data.azurerm_kubernetes_cluster.demo.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:flux-system:kustomize-controller"
}

