variable "prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "vm_count" {
  type = number
}

variable "vm_size" {
  type = string
}

variable "vm_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "admin_username" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "host_pool_name" {
  type = string
}

variable "registration_token" {
  type      = string
  sensitive = true
}

variable "user_object_ids" {
  type    = list(string)
  default = []
}

variable "tags" {
  type = map(string)
}
