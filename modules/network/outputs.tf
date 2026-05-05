output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "session_host_subnet_id" {
  value = azurerm_subnet.session_hosts.id
}
