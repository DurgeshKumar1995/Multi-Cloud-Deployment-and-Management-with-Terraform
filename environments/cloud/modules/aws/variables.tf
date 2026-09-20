variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "ami_id" {
  description = "Optional pinned Ubuntu AMI. Empty selects the latest official Canonical Ubuntu 24.04 AMD64 GP3 image."
  type        = string
}

variable "instance_type" {
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
