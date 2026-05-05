resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.prefix}-avd-${var.environment}-${var.location}"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "session_hosts" {
  name                 = "snet-session-hosts"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.session_host_subnet_prefix]
}

# NSG for session host subnet.
# AVD uses reverse-connect: session hosts dial OUT to the control plane,
# users connect THROUGH the control plane. There is no inbound from internet
# to the VMs, so we only need outbound rules.
resource "azurerm_network_security_group" "session_hosts" {
  name                = "nsg-${var.prefix}-avd-sh-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Outbound to the AVD control plane (gateway, broker, diagnostics).
  security_rule {
    name                       = "AllowOutbound-AVD-ControlPlane"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "WindowsVirtualDesktop"
  }

  # Outbound to AzureCloud — covers Entra ID, storage, agent updates, etc.
  security_rule {
    name                       = "AllowOutbound-AzureCloud"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
  }

  # Allow Windows activation against KMS / Azure metadata service.
  security_rule {
    name                       = "AllowOutbound-AzureKMS"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1688"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "session_hosts" {
  subnet_id                 = azurerm_subnet.session_hosts.id
  network_security_group_id = azurerm_network_security_group.session_hosts.id
}
