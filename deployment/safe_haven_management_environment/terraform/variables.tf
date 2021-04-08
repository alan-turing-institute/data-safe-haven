
################################################
# DNS
################################################

# variable "dns_rg_name" {
#   type = string
# }

# variable "dns_rg_location" {
#   type = string
# }

################################################
# Key Vault
################################################

variable "kv_rg_name" {
  type = string
}

variable "kv_rg_location" {
  type = string
}

variable "kv_name" {
  type = string
}

variable "kv_security_group_id" {
  type = string
}

variable "kv_secret_name_shm_aad_emergency_admin_username" {
  type = string
}

variable "kv_secret_value_shm_aad_emergency_admin_username" {
  type = string
  sensitive = true
}

variable "kv_secret_name_shm_aad_emergency_admin_password" {
  type = string
}

variable "kv_secret_value_shm_aad_emergency_admin_password" {
  type = string
  sensitive = true
}

variable "kv_secret_name_shm_domain_admin_username" {
  type = string
}

variable "kv_secret_value_shm_domain_admin_username" {
  type = string
  sensitive = true
}

variable "kv_secret_name_shm_domain_admin_password" {
  type = string
}

variable "kv_secret_value_shm_domain_admin_password" {
  type = string
  sensitive = true
}

################################################
# Networking
################################################

variable "net_rg_name" {
  type = string
}

variable "net_rg_location" {
  type = string
}

variable "net_name" {
  type = string
}

variable "net_template_path" {
  type = string
}

variable "net_ipaddresses_externalntp" {
  type = list
}

variable "net_nsg_identity_name" {
  type = string
}

variable "net_p2s_vpn_certificate" {
  type = string
}

variable "net_shm_id" {
  type = string
}

variable "net_subnet_firewall_cidr" {
  type = string
}

variable "net_subnet_firewall_name" {
  type = string
}

variable "net_subnet_gateway_cidr" {
  type = string
}

variable "net_subnet_gateway_name" {
  type = string
}

variable "net_subnet_identity_cidr" {
  type = string
}

variable "net_subnet_identity_name" {
  type = string
}

variable "net_virtual_network_name" {
  type = string
}

variable "net_vnet_cidr" {
  type = string
}

variable "net_vnet_dns_dc1" {
  type = string
}

variable "net_vnet_dns_dc2" {
  type = string
}

variable "net_vpn_cidr" {
  type = string
}

################################################
# DC
################################################

variable "dc_rg_name" {
  type = string
}

variable "dc_rg_location" {
  type = string
}

variable "dc_rg_name_bootdiagnostics" {
  type = string
}

variable "dc_sa_name_bootdiagnostics" {
  type = string
}

variable "dc_rg_name_artifacts" {
  type = string
}

variable "dc_sa_name_artifacts" {
  type = string
}