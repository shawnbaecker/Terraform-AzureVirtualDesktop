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

variable "host_pool_type" {
  type = string
}

variable "load_balancer_type" {
  type = string
}

variable "max_sessions_per_host" {
  type = number
}

variable "user_object_ids" {
  type    = list(string)
  default = []
}

variable "tags" {
  type = map(string)
}
