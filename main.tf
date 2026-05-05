# Resource group hosts everything in this stack.
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}-avd-${var.environment}-${var.location}"
  location = var.location
  tags     = var.tags
}

# 1. Network — VNet, subnet, NSG locked down to outbound-only AVD service tags.
module "network" {
  source = "./modules/network"

  prefix                     = var.prefix
  environment                = var.environment
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  vnet_address_space         = var.vnet_address_space
  session_host_subnet_prefix = var.session_host_subnet_prefix
  tags                       = var.tags
}

# 2. AVD control-plane objects — host pool, registration token, app group, workspace.
module "avd" {
  source = "./modules/avd"

  prefix                = var.prefix
  environment           = var.environment
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  host_pool_type        = var.host_pool_type
  load_balancer_type    = var.host_pool_load_balancer_type
  max_sessions_per_host = var.max_sessions_per_host
  user_object_ids       = var.avd_user_object_ids
  tags                  = var.tags
}

# 3. Session hosts — NICs, VMs, Entra-join + AVD agent extensions, login RBAC.
module "session_hosts" {
  source = "./modules/session-hosts"

  prefix              = var.prefix
  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.network.session_host_subnet_id
  vm_count            = var.session_host_count
  vm_size             = var.session_host_vm_size
  vm_image            = var.session_host_image
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  host_pool_name      = module.avd.host_pool_name
  registration_token  = module.avd.registration_token
  user_object_ids     = var.avd_user_object_ids
  tags                = var.tags
}
