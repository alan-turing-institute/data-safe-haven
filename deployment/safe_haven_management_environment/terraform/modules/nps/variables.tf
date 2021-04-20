variable "rg_name" {
  type = string
}
variable "rg_location" {
  type = string
}
variable "template_name" {
  type = string
}
variable "template_path" {
  type = string
}
variable "administrator_password" {
  type = string
  sensitive = true
}
variable "administrator_user" {
  type = string
}
variable "bootdiagnostics_account_name" {
  type = string
}
variable "domain_join_password" {
  type = string
  sensitive = true
}
variable "domain_join_user" {
  type = string
}
variable "domain_name" {
  type = string
}
variable "data_disk_size_gb" {
  type = number
}
variable "data_disk_type" {
  type = string
}
variable "host_name" {
  type = string
}
variable "ip_address" {
  type = string
}
variable "os_disk_size_gb" {
  type = number
}
variable "os_disk_type" {
  type = string
}
variable "vm_name" {
  type = string
}
variable "vm_size" {
  type = string
}
variable "ou_path" {
  type = string
}
variable "virtual_network_name" {
  type = string
}
variable "virtual_network_resource_group" {
  type = string
}
variable "virtual_network_subnet" {
  type = string
}
