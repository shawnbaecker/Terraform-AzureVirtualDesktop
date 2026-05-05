output "resource_group" {
  description = "Resource group containing the AVD lab."
  value       = azurerm_resource_group.main.name
}

output "workspace_name" {
  description = "Workspace users will subscribe to in the Remote Desktop client."
  value       = module.avd.workspace_name
}

output "host_pool_name" {
  value = module.avd.host_pool_name
}

output "session_host_names" {
  value = module.session_hosts.vm_names
}

output "remote_desktop_web_client" {
  description = "Sign in here with the Entra user(s) you assigned in avd_user_object_ids."
  value       = "https://client.wvd.microsoft.com/arm/webclient/"
}
