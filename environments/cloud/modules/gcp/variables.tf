variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zones" {
  type = list(string)
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
