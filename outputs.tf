output "oidc_issuer_url" {
  value = "${data.azurerm_kubernetes_cluster.demo.oidc_issuer_url}"
}

output "user_assigned_identity_clientid" {
  value = "${azurerm_user_assigned_identity.demo.client_id}"
}
