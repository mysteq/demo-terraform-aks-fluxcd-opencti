output "id_workload" {
  value = azurerm_user_assigned_identity.id_workload.client_id
}

output "id_identity" {
  value = azurerm_user_assigned_identity.id_identity.client_id
}
