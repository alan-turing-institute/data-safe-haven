variable "rg_name" {
  type = string
}

variable "rg_location" {
  type = string
}

variable "name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "secret_name_shm_aad_emergency_admin_username" {
  type = string
}

variable "secret_value_shm_aad_emergency_admin_username" {
  type = string
  sensitive = true
}

variable "secret_name_shm_aad_emergency_admin_password" {
  type = string
}

variable "secret_value_shm_aad_emergency_admin_password" {
  type = string
  sensitive = true
}

variable "secret_name_shm_domain_admin_username" {
  type = string
}

variable "secret_value_shm_domain_admin_username" {
  type = string
  sensitive = true
}

variable "secret_name_shm_domain_admin_password" {
  type = string
}

variable "secret_value_shm_domain_admin_password" {
  type = string
  sensitive = true
}

