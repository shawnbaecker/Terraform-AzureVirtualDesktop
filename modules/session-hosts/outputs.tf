output "vm_names" {
  value = azurerm_windows_virtual_machine.session_host[*].name
}

output "vm_ids" {
  value = azurerm_windows_virtual_machine.session_host[*].id
}

output "private_ip_addresses" {
  value = azurerm_network_interface.session_host[*].private_ip_address
}
