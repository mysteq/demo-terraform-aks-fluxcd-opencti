locals {
  solution        = "opencti"
  location        = "westeurope"
  shortlocation   = "westeu"
  shorterlocation = "we"
  environment     = "demo"

  primary_suffix   = "-${local.solution}-${local.environment}-${local.shortlocation}"
  secondary_suffix = "-${local.solution}-${local.shorterlocation}"

  tags = {
    environment  = "${local.environment}"
    solution     = "${local.solution}"
    deletiondate = "2023-08-31"
    createdby    = "ketil"
    source       = "terraform"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg${local.primary_suffix}"
  location = local.location

  tags = local.tags

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec  sed -i '' -r 's/resourceGroup: (.*)/resourceGroup: ${azurerm_resource_group.rg.name}/g' {} +"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "id_workload" {
  name                = "id${local.primary_suffix}-workload"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/client-id: (.*)/client-id: ${azurerm_user_assigned_identity.id_workload.client_id}/g' {} +"
  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/clientId: (.*)/clientId: ${azurerm_user_assigned_identity.id_workload.client_id}/g' {} +"
  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/clientID: (.*)/clientID: \"${azurerm_user_assigned_identity.id_workload.client_id}\"/g' {} +"
  }

  tags = local.tags
}

resource "azurerm_user_assigned_identity" "id_identity" {
  name                = "id${local.primary_suffix}-identity"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  tags = local.tags
}

resource "random_id" "id" {
  byte_length = 2
}

resource "azurerm_key_vault" "kv" {
  name                        = "kv${local.secondary_suffix}-${lower(random_id.id.hex)}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = true
  enable_rbac_authorization   = true
  enabled_for_disk_encryption = true

  sku_name = "standard"

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = ["79.160.225.150", "87.248.1.150"]
    virtual_network_subnet_ids = [azurerm_subnet.snet.id]
  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/keyvaultName: (.*)/keyvaultName: ${azurerm_key_vault.kv.name}/g' {} +"
  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec sed -i '' -r 's/vaultUrl: (.*)/vaultUrl: \"${replace(azurerm_key_vault.kv.vault_uri, "/", "\\/")}\"/g' {} +"
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "ra_current" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_key" "kv_key_sops" {
  name         = "sops-key"
  key_vault_id = azurerm_key_vault.kv.id
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
    command = "sed -i '' -r 's/azure_keyvault: (.*)/azure_keyvault: ${replace(azurerm_key_vault.kv.vault_uri, "/\\//", "\\/")}keys\\/${azurerm_key_vault_key.kv_key_sops.name}\\/${azurerm_key_vault_key.kv_key_sops.version}/g' .sops.yaml"
  }

  depends_on = [azurerm_role_assignment.ra_current]
  tags       = local.tags
}

resource "azurerm_key_vault_key" "kv_key_kms" {
  name         = "etcd-encryption-key"
  key_vault_id = azurerm_key_vault.kv.id
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

  # rotation_policy {
  #   automatic {
  #     time_before_expiry = "P30D"
  #   }

  #   expire_after         = "P90D"
  #   notify_before_expiry = "P29D"
  # }

  depends_on = [azurerm_role_assignment.ra_current]
  tags       = local.tags
}

resource "azurerm_key_vault_key" "kv_key_des" {
  name         = "des-key"
  key_vault_id = azurerm_key_vault.kv.id
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
      time_before_expiry = "P120D"
    }

    expire_after         = "P180D"
    notify_before_expiry = "P160D"
  }

  depends_on = [azurerm_role_assignment.ra_current]
  tags       = local.tags
}

resource "azurerm_disk_encryption_set" "des" {
  key_vault_key_id          = azurerm_key_vault_key.kv_key_des.id
  name                      = "des${local.primary_suffix}"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  auto_key_rotation_enabled = true

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.id_identity.id,
    ]
  }
}

resource "azurerm_role_assignment" "ra_identity_kvcryptoserviceencryptionuser" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.id_identity.principal_id
}

resource "azurerm_role_assignment" "ra_identity_kvcryptouser" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.id_identity.principal_id
}

resource "azurerm_role_assignment" "ra_identity_kvcontibutor" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = azurerm_user_assigned_identity.id_identity.principal_id
}

resource "azurerm_role_assignment" "ra_workload_kvsecretsofficer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.id_workload.principal_id
}

resource "azurerm_role_assignment" "ra_workload_kvcryptoofficer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = azurerm_user_assigned_identity.id_workload.principal_id
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg${local.primary_suffix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "nsg_rule_inbound_allow_https" {
  name                        = "InboundAllowHttps"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
  priority                    = 500
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet${local.primary_suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  address_space = ["10.140.0.0/16"]
  tags          = local.tags
}

resource "azurerm_role_assignment" "ra_identity_netcontributor" {
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.id_identity.principal_id
}

resource "azurerm_subnet" "snet" {
  name                                      = "aks-${local.solution}"
  resource_group_name                       = azurerm_resource_group.rg.name
  virtual_network_name                      = azurerm_virtual_network.vnet.name
  address_prefixes                          = ["10.140.0.0/22"]
  private_endpoint_network_policies_enabled = true

  service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

resource "azurerm_subnet_network_security_group_association" "snet_nsg" {
  subnet_id                 = azurerm_subnet.snet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

module "kubernetes" {
  #source  = "amestofortytwo/aks/azurerm"
  #version = "3.0.0"
  source = "../../amestofortytwo/github/terraform-azurerm-aks"
  #  source = "github.com/amestofortytwo/terraform-azurerm-aks?ref=53fa0f2f4b3e6ce3b7324fed6b4d2843b8a9cfbf"

  name                = "aks${local.primary_suffix}"
  kubernetes_version  = "1.27"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  workload_identity_enabled = true
  automatic_channel_upgrade = "node-image"

  identity = {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.id_identity.id]
  }

  kms_enabled                  = true
  kms_key_vault_key_id         = azurerm_key_vault_key.kv_key_kms.id
  kms_key_vault_network_access = "Private"
  disk_encryption_set_id       = azurerm_disk_encryption_set.des.id

  network_profile = {
    network_plugin = "azure"
    network_policy = "azure"
    vnet_subnet_id = azurerm_subnet.snet.id
  }

  default_node_pool = {
    name   = "default"
    os_sku = "AzureLinux"
    autoscale = {
      min_count = 1
      max_count = 3
    }
    enable_auto_scaling          = true
    vm_size                      = "Standard_B2ms"
    only_critical_addons_enabled = true
  }

  additional_node_pools = [
    {
      name                = "pool1"
      min_count           = 1
      max_count           = 2
      enable_auto_scaling = true
      vm_size             = "Standard_B4ms"
      linux_os_config = {
        sysctl_config = {
          "vm_max_map_count" = "262144"
        }
      }
    },
    {
      name                = "spot1"
      os_sku              = "AzureLinux"
      min_count           = 1
      max_count           = 2
      enable_auto_scaling = true
      vm_size             = "Standard_E4_v3"
      spot_max_price      = "0.04"
      eviction_policy     = "Delete"
      node_taints         = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
      priority            = "Spot"
      linux_os_config = {
        sysctl_config = {
          "vm_max_map_count" = "262144"
        }
      }
    },
    {
      name                = "spot2"
      os_sku              = "AzureLinux"
      min_count           = 1
      max_count           = 2
      enable_auto_scaling = true
      vm_size             = "Standard_E4_v4"
      spot_max_price      = "0.04"
      eviction_policy     = "Delete"
      node_taints         = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
      priority            = "Spot"
      linux_os_config = {
        sysctl_config = {
          "vm_max_map_count" = "262144"
        }
      }
    },
    {
      name                = "spot3"
      os_sku              = "AzureLinux"
      min_count           = 1
      max_count           = 2
      enable_auto_scaling = true
      vm_size             = "Standard_E4s_v3"
      spot_max_price      = "0.04"
      eviction_policy     = "Delete"
      node_taints         = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
      priority            = "Spot"
      linux_os_config = {
        sysctl_config = {
          "vm_max_map_count" = "262144"
        }
      }
    },
  ]

  tags = local.tags
}

//data "azurerm_kubernetes_cluster" "demo" {
//  name                = "demo-aks-westeu"
//  resource_group_name = azurerm_resource_group.rg.name
//
//  depends_on = [
//    module.kubernetes
//  ]
//}

resource "null_resource" "null_resource" {
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name aks${local.primary_suffix} --overwrite-existing --subscription ${data.azurerm_client_config.current.subscription_id}"
  }

  depends_on = [
    module.kubernetes
  ]
}

resource "azurerm_role_assignment" "ra_current_aksrbacclusteradmin" {
  scope                = module.kubernetes.aks_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_federated_identity_credential" "fic_sops" {
  name                = "fic${local.primary_suffix}-sops"
  resource_group_name = azurerm_resource_group.rg.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.id_workload.id
  subject             = "system:serviceaccount:flux-system:kustomize-controller"
}

/*resource "azurerm_federated_identity_credential" "demo_identity_opencti" {
  name                = "demo-aks-westeu-opencti"
  resource_group_name = azurerm_resource_group.rg.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:opencti:opencti-sa"
}

resource "azurerm_federated_identity_credential" "demo_identity_opencti-elasticsearch" {
  name                = "demo-aks-westeu-opencti-elasticsearch"
  resource_group_name = azurerm_resource_group.rg.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:opencti-elasticsearch:opencti-elasticsearch-sa"
}

resource "azurerm_federated_identity_credential" "demo_identity_opencti-rabbitmq" {
  name                = "demo-aks-westeu-opencti-rabbitmq"
  resource_group_name = azurerm_resource_group.rg.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:opencti-rabbitmq:opencti-rabbitmq-sa"
}

resource "azurerm_federated_identity_credential" "demo_identity_opencti-minio" {
  name                = "demo-aks-westeu-opencti-minio"
  resource_group_name = azurerm_resource_group.rg.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.demo.id
  subject             = "system:serviceaccount:opencti-minio:opencti-minio-sa"
}*/

resource "azurerm_federated_identity_credential" "fic_external-dns" {
  name                = "fic${local.primary_suffix}-external-dns"
  resource_group_name = azurerm_resource_group.rg.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.id_workload.id
  subject             = "system:serviceaccount:external-dns:external-dns-sa"
}

resource "azurerm_federated_identity_credential" "fic_secret-store" {
  name                = "fic${local.primary_suffix}-secret-store"
  resource_group_name = azurerm_resource_group.rg.name
  issuer              = module.kubernetes.oidc_issuer_url
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.id_workload.id
  subject             = "system:serviceaccount:secret-store:secret-store-sa"
}

resource "azurerm_storage_account" "st" {
  name                             = "st${replace(local.secondary_suffix,"-","")}${lower(random_id.id.hex)}"
  resource_group_name              = azurerm_resource_group.rg.name
  location                         = azurerm_resource_group.rg.location
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  enable_https_traffic_only        = true
  allow_nested_items_to_be_public  = false
  min_tls_version                  = "TLS1_2"
  cross_tenant_replication_enabled = false
  default_to_oauth_authentication  = true

  network_rules {
    default_action             = "Deny"
    ip_rules                   = ["79.160.225.150", "87.248.1.150"]
    virtual_network_subnet_ids = [azurerm_subnet.snet.id]
  }

  #  provisioner "local-exec" {
  #    command = "sed -i '' -r 's/azurestorageaccountname: (.*)/azurestorageaccountname: ${azurerm_storage_account.opencti.name}/g' cluster/infra/storage/secret-sa.yaml"
  #  }

  #  provisioner "local-exec" {
  #    command = "sed -i '' -r 's/azurestorageaccountkey: (.*)/azurestorageaccountkey: ${replace(azurerm_storage_account.opencti.primary_access_key, "/\\//", "\\/")}/g' cluster/infra/storage/secret-sa.yaml"
  #  }

  provisioner "local-exec" {
    command = "find cluster/ -type f -name '*.yaml' -exec  sed -i '' -r 's/storageAccount: (.*)/storageAccount: ${azurerm_storage_account.st.name}/g' {} +"
  }

  #  provisioner "local-exec" {
  #    command = "sops -e --in-place cluster/infra/storage/secret-sa.yaml"
  #  }

  #  provisioner "local-exec" {
  #    when    = destroy
  #    command = "sops -d --in-place cluster/infra/storage/secret-sa.yaml"
  #  }

  depends_on = [azurerm_key_vault_key.kv_key_sops]
  tags       = local.tags
}

resource "azurerm_role_assignment" "ra_current_stfiledataprivilegedcontributor" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "ra_identity_stcontributor" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.id_identity.principal_id
}

resource "azurerm_key_vault_secret" "kv_secret_tenantid" {
  name         = "azuretenantid"
  value        = data.azurerm_client_config.current.tenant_id
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "azurerm_key_vault_secret" "kv_secret_subscriptionid" {
  name         = "azuresubscriptionid"
  value        = data.azurerm_client_config.current.subscription_id
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "azurerm_key_vault_secret" "kv_secret_resourcegroupname" {
  name         = "azurereourcegroupname"
  value        = azurerm_resource_group.rg.name
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "azurerm_key_vault_secret" "kv_secret_storageaccountname" {
  name         = "storageaccountname"
  value        = azurerm_storage_account.st.name
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "azurerm_key_vault_secret" "kv_secret_storageaccountkey" {
  name         = "storageaccountkey"
  value        = azurerm_storage_account.st.primary_access_key
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_password" "elasticsearch-bootstrap-password" {
  length  = 16
  special = false
  upper   = false
}

resource "azurerm_key_vault_secret" "kv_secret_elasticsearch-bootstrap-password" {
  name         = "elasticsearch-bootstrap-password"
  value        = random_password.elasticsearch-bootstrap-password.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_uuid" "opencti_token" {
}

resource "azurerm_key_vault_secret" "kv_secret_opencti_token" {
  name         = "opencti-token"
  value        = random_uuid.opencti_token.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

# resource "random_password" "erlang_cookie" {
#   length           = 16
#   special          = true
#   override_special = "!#$%&*()-_=+[]{}<>:?"
# }

# resource "azurerm_key_vault_secret" "erlang_cookie" {
#   name         = "erlang-cookie"
#   value        = random_password.erlang_cookie.result
#   key_vault_id = azurerm_key_vault.kv.id

#   depends_on = [azurerm_role_assignment.ra_current]
# }

resource "random_uuid" "minio_root_user" {
}

resource "azurerm_key_vault_secret" "kv_secret_minio_root_user" {
  name         = "minio-root-user"
  value        = random_uuid.minio_root_user.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_password" "minio_root_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "kv_secret_minio_root_password" {
  name         = "minio-root-password"
  value        = random_password.minio_root_password.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_uuid" "rabbitmq_default_user" {
}

resource "azurerm_key_vault_secret" "kv_secret_rabbitmq_default_user" {
  name         = "rabbitmq-default-user"
  value        = random_uuid.rabbitmq_default_user.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_password" "rabbitmq_default_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "kv_secret_rabbitmq_default_password" {
  name         = "rabbitmq-default-password"
  value        = random_password.rabbitmq_default_password.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_password" "opencti_admin_email" {
  length  = 16
  special = false
  upper   = false
}

resource "azurerm_key_vault_secret" "kv_secret_opencti_admin_email" {
  name         = "opencti-admin-email"
  value        = "${random_password.opencti_admin_email.result}@none.local"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_password" "opencti_admin_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "kv_secret_opencti_admin_password" {
  name         = "opencti-admin-password"
  value        = random_password.opencti_admin_password.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "azurerm_key_vault_secret" "kv_secret_elasticsearch-user" {
  name         = "elasticsearch-user"
  value        = "elastic"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_password" "elasticsearch-password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "kv_secret_elasticsearch-password" {
  name         = "elasticsearch-password"
  value        = random_password.elasticsearch-password.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "azurerm_key_vault_secret" "kv_secret_elasticsearch-roles" {
  name         = "elasticsearch-roles"
  value        = "superuser"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_uuid" "connector_id_alienvault" {
}

resource "azurerm_key_vault_secret" "kv_secret_alientvault-connector-id" {
  name         = "alienvault-connector-id"
  value        = random_uuid.connector_id_alienvault.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

resource "random_uuid" "connector_id_opencti" {
}

resource "azurerm_key_vault_secret" "kv_secret_opencti-connector-id" {
  name         = "opencti-connector-id"
  value        = random_uuid.connector_id_opencti.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.ra_current]
}

# resource "azurerm_dns_zone" "dnszone" {
#   name                = "k8s.4t2.no"
#   resource_group_name = azurerm_resource_group.rg.name

#   tags = local.tags
# }

# resource "azurerm_role_assignment" "ra_workload_dnszonecontributor" {
#   scope                = azurerm_dns_zone.dnszone.id
#   role_definition_name = "DNS Zone Contributor"
#   principal_id         = azurerm_user_assigned_identity.id_workload.principal_id
# }
