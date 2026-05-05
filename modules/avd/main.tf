###############################
# Host Pool
###############################
# The logical grouping of session host VMs. This is the "compute layer."
resource "azurerm_virtual_desktop_host_pool" "main" {
  name                     = "hp-${var.prefix}-avd-${var.environment}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  type                     = var.host_pool_type
  load_balancer_type       = var.load_balancer_type
  maximum_sessions_allowed = var.max_sessions_per_host
  preferred_app_group_type = "Desktop"
  validate_environment     = false
  start_vm_on_connect      = false # set to true once you grant the AVD SP "Power On Off Contributor" on the subscription

  # custom_rdp_properties tell the RDP client this is an Entra-joined pool
  # so single sign-on works correctly. Without targetisaadjoined:i:1 you'll
  # be prompted for credentials twice (gateway + VM).
  custom_rdp_properties = "targetisaadjoined:i:1;enablerdsaadauth:i:1;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:1;redirectprinters:i:1;drivestoredirect:s:*"

  tags = var.tags
}

###############################
# Registration Token
###############################
# Session hosts use this token to join the host pool. It must not expire
# during apply, and we don't want a stale token sitting in state forever.
# time_rotating regenerates the token every 29 days (max is 30).
resource "time_rotating" "registration_token" {
  rotation_days = 29
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "main" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.main.id
  expiration_date = time_rotating.registration_token.rotation_rfc3339
}

###############################
# Application Group
###############################
# Defines what users get. "Desktop" = full Windows desktop session.
# "RemoteApp" would publish individual apps without a full desktop.
resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                = "ag-${var.prefix}-avd-desktop-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  host_pool_id        = azurerm_virtual_desktop_host_pool.main.id
  type                = "Desktop"
  friendly_name       = "Baecker AVD Desktop"
  description         = "Full Windows 11 multi-session desktop"
  tags                = var.tags
}

###############################
# Workspace
###############################
# The user-facing container that bundles application groups together.
# This is what users subscribe to in the Remote Desktop client.
resource "azurerm_virtual_desktop_workspace" "main" {
  name                = "ws-${var.prefix}-avd-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  friendly_name       = "Baecker AVD Lab"
  description         = "AVD lab workspace built with Terraform"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "main" {
  workspace_id         = azurerm_virtual_desktop_workspace.main.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}

###############################
# RBAC — assign users to the app group
###############################
# Without this role, users can authenticate but won't see any resources
# when they sign into the AVD client.
resource "azurerm_role_assignment" "avd_users" {
  for_each             = toset(var.user_object_ids)
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = each.value
}
