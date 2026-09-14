output "public_ip" {
  value = azurerm_public_ip.load_balancer.ip_address
}

output "endpoint_hostname" {
  value = azurerm_public_ip.load_balancer.fqdn
}

output "endpoint_url" {
  value = "http://${azurerm_public_ip.load_balancer.fqdn}"
}

output "storage_account" {
  value = azurerm_storage_account.backup.name
}

output "database_endpoint" {
  value     = try(azurerm_postgresql_flexible_server.database[0].fqdn, null)
  sensitive = true
}
