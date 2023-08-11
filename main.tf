
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
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/client-id: (.*)/client-id: ${azurerm_user_assigned_identity.demo.client_id}/g' {} +"
  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/clientId: (.*)/clientId: ${azurerm_user_assigned_identity.demo.client_id}/g' {} +"
  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/clientID: (.*)/clientID: \"${azurerm_user_assigned_identity.demo.client_id}\"/g' {} +"
  }

}

resource "random_id" "id" {
  byte_length = 2
}

resource "azurerm_key_vault" "demo" {
  name                       = "demo-aks-westeu-${lower(random_id.id.hex)}"
  location                   = azurerm_resource_group.demo.location
  resource_group_name        = azurerm_resource_group.demo.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  enable_rbac_authorization  = true

  sku_name = "standard"

  network_acls {
    bypass                     = "None"
    default_action             = "Deny"
    ip_rules                   = ["79.160.225.150"]
    virtual_network_subnet_ids = [azurerm_subnet.demo-aks.id]
  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/keyvaultName: (.*)/keyvaultName: ${azurerm_key_vault.demo.name}/g' {} +"
  }
}

resource "azurerm_role_assignment" "demo_me" {
  scope                = azurerm_key_vault.demo.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "demo_uai" {
  scope                = azurerm_key_vault.demo.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = azurerm_user_assigned_identity.demo.principal_id
}

resource "azurerm_role_assignment" "demo_uai2" {
  scope                = azurerm_key_vault.demo.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.demo.principal_id
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
    command = "sed -i '' -r 's/azure_keyvault: (.*)/azure_keyvault: ${replace(azurerm_key_vault.demo.vault_uri, "/\\//", "\\/")}keys\\/${azurerm_key_vault_key.demo.name}\\/${azurerm_key_vault_key.demo.version}/g' .sops.yaml"
  }

  provisioner "local-exec" {
    command = "sops -e --in-place cluster/app/opencti-elasticsearch/secret.yaml"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "sops -d --in-place cluster/app/opencti-elasticsearch/secret.yaml"
  }

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "azurerm_virtual_network" "demo" {
  name                = "demo-aks-westeu"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location

  address_space = ["10.140.0.0/16"]
}

resource "azurerm_subnet" "demo-aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = ["10.140.0.0/22"]

  service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

module "kubernetes" {
  #source  = "amestofortytwo/aks/azurerm"
  #version = "3.0.0"
  source = "../../amestofortytwo/github/terraform-azurerm-aks"
  #  source = "github.com/amestofortytwo/terraform-azurerm-aks?ref=53fa0f2f4b3e6ce3b7324fed6b4d2843b8a9cfbf"

  name                = "demo-aks-westeu"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location

  workload_identity_enabled = true

  key_vault_secrets_provider = {
    enabled                 = true
    secret_rotation_enabled = true
  }

  network_profile = {
    network_plugin = "azure"
    vnet_subnet_id = azurerm_subnet.demo-aks.id
  }

  default_node_pool = {
    name                 = "default"
    node_count           = 2
    vm_size              = "Standard_B2ms"
    virtual_network_name = azurerm_virtual_network.demo.name
  }

  additional_node_pools = [
    {
      name                = "pool1"
      min_count           = 1
      max_count           = 4
      enable_auto_scaling = true
      vm_size             = "Standard_B4ms"
    },
  ]

  tags = {
    environment = "demo"
  }
}

//data "azurerm_kubernetes_cluster" "demo" {
//  name                = "demo-aks-westeu"
//  resource_group_name = azurerm_resource_group.demo.name
//
//  depends_on = [
//    module.kubernetes
//  ]
//}

resource "null_resource" "demo" {
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.demo.name} --name demo-aks-westeu --overwrite-existing --subscription ${data.azurerm_client_config.current.subscription_id}"
  }

  depends_on = [
    module.kubernetes
  ]
}

resource "azurerm_role_assignment" "example" {
  #scope                = data.azurerm_kubernetes_cluster.demo.id
  scope                = module.kubernetes.aks_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_federated_identity_credential" "demo" {
  name                = "demo-aks-westeu-sops"
  resource_group_name = azurerm_resource_group.demo.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:flux-system:kustomize-controller"
}

resource "azurerm_federated_identity_credential" "demo_identity_opencti" {
  name                = "demo-aks-westeu-opencti"
  resource_group_name = azurerm_resource_group.demo.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:opencti:opencti-sa"
}

resource "azurerm_federated_identity_credential" "demo_identity_opencti-elasticsearch" {
  name                = "demo-aks-westeu-opencti-elasticsearch"
  resource_group_name = azurerm_resource_group.demo.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:opencti-elasticsearch:opencti-elasticsearch-sa"
}

resource "azurerm_federated_identity_credential" "demo_identity_opencti-rabbitmq" {
  name                = "demo-aks-westeu-opencti-rabbitmq"
  resource_group_name = azurerm_resource_group.demo.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:opencti-rabbitmq:opencti-rabbitmq-sa"
}

resource "azurerm_federated_identity_credential" "demo_identity_opencti-minio" {
  name                = "demo-aks-westeu-opencti-minio"
  resource_group_name = azurerm_resource_group.demo.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:opencti-minio:opencti-minio-sa"
}

resource "azurerm_federated_identity_credential" "demo_identity_external-dns" {
  name                = "demo-aks-westeu-external-dns"
  resource_group_name = azurerm_resource_group.demo.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:external-dns:external-dns-sa"
}

resource "azurerm_storage_account" "opencti" {
  name                             = "stdemoakswesteu${lower(random_id.id.hex)}"
  resource_group_name              = azurerm_resource_group.demo.name
  location                         = azurerm_resource_group.demo.location
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  enable_https_traffic_only        = true
  allow_nested_items_to_be_public  = false
  min_tls_version                  = "TLS1_2"
  cross_tenant_replication_enabled = false
  default_to_oauth_authentication  = true

  network_rules {
    default_action             = "Deny"
    ip_rules                   = ["79.160.225.150"]
    virtual_network_subnet_ids = [azurerm_subnet.demo-aks.id]
  }

  provisioner "local-exec" {
    command = "sed -i '' -r 's/azurestorageaccountname: (.*)/azurestorageaccountname: ${azurerm_storage_account.opencti.name}/g' cluster/infra/storage/secret-sa.yaml"
  }

  provisioner "local-exec" {
    command = "sed -i '' -r 's/azurestorageaccountkey: (.*)/azurestorageaccountkey: ${replace(azurerm_storage_account.opencti.primary_access_key, "/\\//", "\\/")}/g' cluster/infra/storage/secret-sa.yaml"
  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec  sed -i '' -r 's/storageAccount: (.*)/storageAccount: ${azurerm_storage_account.opencti.name}/g' {} +"
  }

  provisioner "local-exec" {
    command = "sops -e --in-place cluster/infra/storage/secret-sa.yaml"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "sops -d --in-place cluster/infra/storage/secret-sa.yaml"
  }

  depends_on = [azurerm_key_vault_key.demo]
}

resource "azurerm_role_assignment" "demo_sa_me" {
  scope                = azurerm_storage_account.opencti.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "demo_sa_aks" {
  scope                = azurerm_storage_account.opencti.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = module.kubernetes.identity[0].principal_id
}

resource "random_uuid" "opencti_token" {
}

resource "azurerm_key_vault_secret" "opencti_token" {
  name         = "opencti-token"
  value        = random_uuid.opencti_token.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_password" "erlang_cookie" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "erlang_cookie" {
  name         = "erlang-cookie"
  value        = random_password.erlang_cookie.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_uuid" "minio_root_user" {
}

resource "azurerm_key_vault_secret" "minio_root_user" {
  name         = "minio-root-user"
  value        = random_uuid.minio_root_user.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_password" "minio_root_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "minio_root_password" {
  name         = "minio-root-password"
  value        = random_password.minio_root_password.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_uuid" "rabbitmq_default_user" {
}

resource "azurerm_key_vault_secret" "rabbitmq_default_user" {
  name         = "rabbitmq-default-user"
  value        = random_uuid.rabbitmq_default_user.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_password" "rabbitmq_default_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "rabbitmq_default_password" {
  name         = "rabbitmq-default-password"
  value        = random_password.rabbitmq_default_password.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_password" "opencti_admin_email" {
  length  = 16
  special = false
  upper   = false
}

resource "azurerm_key_vault_secret" "opencti_admin_email" {
  name         = "opencti-admin-email"
  value        = "${random_password.opencti_admin_email.result}@none.local"
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_password" "opencti_admin_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "opencti_admin_password" {
  name         = "opencti-admin-password"
  value        = random_password.opencti_admin_password.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "azurerm_key_vault_secret" "elasticsearch-user" {
  name         = "elasticsearch-user"
  value        = "elastic"
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_password" "elasticsearch-password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "elasticsearch-password" {
  name         = "elasticsearch-password"
  value        = random_password.elasticsearch-password.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "azurerm_key_vault_secret" "elasticsearch-roles" {
  name         = "elasticsearch-roles"
  value        = "superuser"
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_uuid" "connector_id_alienvault" {
}

resource "azurerm_key_vault_secret" "alientvault-connector-id" {
  name         = "alienvault-connector-id"
  value        = random_uuid.connector_id_alienvault.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "random_uuid" "connector_id_opencti" {
}

resource "azurerm_key_vault_secret" "opencti-connector-id" {
  name         = "opencti-connector-id"
  value        = random_uuid.connector_id_opencti.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_role_assignment.demo_me]
}

resource "azurerm_dns_zone" "demo" {
  name                = "k8s.4t2.no"
  resource_group_name = azurerm_resource_group.demo.name
}

resource "azurerm_role_assignment" "demo-dns-uid" {
  scope                = azurerm_dns_zone.demo.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.demo.principal_id
}
