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

variable "vnet_address_space" {
  type = list(string)
}

variable "session_host_subnet_prefix" {
  type = string
}

variable "tags" {
  type = map(string)
}
