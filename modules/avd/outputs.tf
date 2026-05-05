output "host_pool_id" {
  value = azurerm_virtual_desktop_host_pool.main.id
}

output "host_pool_name" {
  value = azurerm_virtual_desktop_host_pool.main.name
}

output "registration_token" {
  description = "Token used by session hosts to register with the host pool. Marked sensitive so it doesn't appear in plan output."
  value       = azurerm_virtual_desktop_host_pool_registration_info.main.token
  sensitive   = true
}

output "workspace_id" {
  value = azurerm_virtual_desktop_workspace.main.id
}

output "workspace_name" {
  value = azurerm_virtual_desktop_workspace.main.name
}

output "application_group_id" {
  value = azurerm_virtual_desktop_application_group.desktop.id
}
