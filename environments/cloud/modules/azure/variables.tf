variable "name_prefix" {
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

variable "admin_username" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type = number
}

variable "health_check_path" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "enable_database" {
  type = bool
}

variable "database_admin_username" {
  type = string
}

variable "database_admin_password" {
  type      = string
  sensitive = true
}

