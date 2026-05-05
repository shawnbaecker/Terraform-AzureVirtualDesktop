###############################
# Naming & location
###############################

variable "prefix" {
  description = "Naming prefix. bkr = Baecker, matches the rest of the multi-cloud lab."
  type        = string
  default     = "bkr"
}

variable "environment" {
  description = "Environment short code (lab, dev, prod)."
  type        = string
  default     = "lab"
}

variable "location" {
  description = "Azure region for all resources. Pick one that supports AVD."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project     = "AVD-Lab"
    Owner       = "Shawn Baecker"
    ManagedBy   = "Terraform"
    Environment = "Lab"
  }
}

###############################
# Networking
###############################

variable "vnet_address_space" {
  description = "Address space for the AVD VNet."
  type        = list(string)
  default     = ["10.50.0.0/16"]
}

variable "session_host_subnet_prefix" {
  description = "Subnet for session host NICs."
  type        = string
  default     = "10.50.1.0/24"
}

###############################
# Session hosts
###############################

variable "session_host_count" {
  description = "Number of session host VMs to deploy."
  type        = number
  default     = 2
}

variable "session_host_vm_size" {
  description = "VM size for session hosts. D2s_v5 is the AVD baseline; B2ms is cheaper for lab use."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "session_host_image" {
  description = "Marketplace image for Windows 11 multi-session AVD."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-avd"
    version   = "latest"
  }
}

variable "admin_username" {
  description = "Local admin username for session hosts."
  type        = string
  default     = "bkradmin"
}

variable "admin_password" {
  description = <<-EOT
    Local admin password for session hosts. Do NOT put this in tfvars.
    Set via environment variable instead:
      PowerShell: $env:TF_VAR_admin_password = "..."
      Bash:       export TF_VAR_admin_password="..."
  EOT
  type        = string
  sensitive   = true
}

###############################
# AVD
###############################

variable "host_pool_type" {
  description = "Pooled (multi-session, cost-efficient) or Personal (1:1 user-to-VM)."
  type        = string
  default     = "Pooled"
  validation {
    condition     = contains(["Pooled", "Personal"], var.host_pool_type)
    error_message = "host_pool_type must be either Pooled or Personal."
  }
}

variable "host_pool_load_balancer_type" {
  description = "BreadthFirst spreads users across hosts (default), DepthFirst fills one host before moving to the next."
  type        = string
  default     = "BreadthFirst"
}

variable "max_sessions_per_host" {
  description = "Maximum concurrent user sessions per session host."
  type        = number
  default     = 4
}

variable "avd_user_object_ids" {
  description = "List of Entra ID object IDs (users or groups) to grant AVD access. Find yours at Entra ID > Users > your account > Object ID."
  type        = list(string)
  default     = []
}
