output "user_assigned_identity_clientid" {
  value = "${azurerm_user_assigned_identity.demo.client_id}"
}
