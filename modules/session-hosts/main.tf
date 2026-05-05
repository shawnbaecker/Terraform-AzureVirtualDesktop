data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

###############################
# NICs — one per session host
###############################
resource "azurerm_network_interface" "session_host" {
  count               = var.vm_count
  name                = "nic-${var.prefix}-avd-sh${count.index + 1}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    # No public IP — session hosts are reached via the AVD control plane.
  }
}

###############################
# Session host VMs (Windows 11 multi-session)
###############################
resource "azurerm_windows_virtual_machine" "session_host" {
  count                 = var.vm_count
  name                  = "vm-${var.prefix}-sh${count.index + 1}"
  computer_name         = "${var.prefix}-sh${count.index + 1}"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.session_host[count.index].id]

  # System-assigned identity is required for the AAD join extension.
  identity {
    type = "SystemAssigned"
  }

  # Trusted Launch Gen2 — same security posture you'd want for STIG-aligned
  # workloads in Gov. Required for many DoD baselines.
  vtpm_enabled        = true
  secure_boot_enabled = true

  os_disk {
    name                 = "osdisk-${var.prefix}-sh${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  # Tells Azure this VM is using a Windows client license (AVD-eligible).
  license_type = "Windows_Client"

  tags = var.tags
}

###############################
# Extension 1: Entra ID join
###############################
# Joins the VM to your Entra tenant. After this runs, the VM is an
# Entra-joined device and users can sign in with their Entra credentials.
resource "azurerm_virtual_machine_extension" "aad_join" {
  count                      = var.vm_count
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags
}

###############################
# Extension 2: AVD agent installation + host pool registration
###############################
# Microsoft publishes a DSC configuration that:
#   1. Installs the AVD agent and boot loader
#   2. Registers the VM with the host pool using the registration token
#   3. Configures the host as Entra-joined (aadJoin = true)
#
# After this runs, the VM appears in the host pool as a session host.
resource "azurerm_virtual_machine_extension" "avd_dsc" {
  count                      = var.vm_count
  name                       = "Microsoft.PowerShell.DSC"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = <<-SETTINGS
    {
      "modulesUrl": "https://raw.githubusercontent.com/Azure/RDS-Templates/master/ARM-wvd-templates/DSC/Configuration.zip",
      "configurationFunction": "Configuration.ps1\\AddSessionHost",
      "properties": {
        "HostPoolName": "${var.host_pool_name}",
        "aadJoin": true,
        "UseAgentDownloadEndpoint": true
      }
    }
  SETTINGS

  protected_settings = <<-PROTECTED
    {
      "properties": {
        "registrationInfoToken": "${var.registration_token}"
      }
    }
  PROTECTED

  # Order matters: AAD join must complete before the AVD agent registers,
  # otherwise the agent registers a non-Entra-joined host and SSO breaks.
  depends_on = [azurerm_virtual_machine_extension.aad_join]
}

###############################
# RBAC — Virtual Machine User Login
###############################
# Without this role, Entra users authenticate to the AVD gateway but get
# rejected at the VM logon. Scoped to the resource group so all session
# hosts inherit it.
resource "azurerm_role_assignment" "vm_user_login" {
  for_each             = toset(var.user_object_ids)
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = each.value
}
