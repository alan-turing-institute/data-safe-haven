variable "rg_name" {
  type = string
}

variable "rg_location" {
  type = string
}

variable "ipaddresses_externalntp" {
  type = list
}

variable "nsg_identity_name" {
  type = string
}

variable "p2s_vpn_certificate" {
  type = string
}

variable "shm_id" {
  type = string
}

variable "subnet_firewall_cidr" {
  type = string
}

variable "subnet_firewall_name" {
  type = string
}

variable "subnet_gateway_cidr" {
  type = string
}

variable "subnet_gateway_name" {
  type = string
}

variable "subnet_identity_cidr" {
  type = string
}

variable "subnet_identity_name" {
  type = string
}

variable "virtual_network_name" {
  type = string
}

variable "vnet_cidr" {
  type = string
}

variable "vnet_dns_dc1" {
  type = string
}

variable "vnet_dns_dc2" {
  type = string
}

variable "vpn_cidr" {
  type = string
}
