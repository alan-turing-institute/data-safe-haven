################################################
# Artifacts
################################################

variable "art_rg_name" {
  type = string
}
variable "art_rg_location" {
  type = string
}
variable "art_sa_name" {
  type = string
}
variable "art_dc_createadpdc_path" {
  type = string
}
variable "art_dc_createadbdc_path" {
  type = string
}
variable "art_dc_config_files_path" {
  type = string
}
variable "art_dc_config_file_disconnect_ad" {
  type = string
}
variable "art_dc_putty_source_uri" {
  type = string 
}
variable "art_nps_config_files_path" {
  type = string 
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
variable "dc_administrator_password" {
  type = string
  sensitive = true
}
variable "dc_administrator_user" {
  type = string
}
variable "dc_artifacts_location" {
  type = string
}
variable "dc_artifacts_location_sas_token" {
  type = string
  sensitive = true
}
variable "dc_bootdiagnostics_account_name" {
  type = string
}
variable "dc_dc1_data_disk_size_gb" {
  type = number
}
variable "dc_dc1_data_disk_type" {
  type = string
}
variable "dc_dc1_host_name" {
  type = string
}
variable "dc_dc1_ip_address" {
  type = string
}
variable "dc_dc1_os_disk_size_gb" {
  type = number
}
variable "dc_dc1_os_disk_type" {
  type = string
}
variable "dc_dc1_vm_name" {
  type = string
}
variable "dc_dc1_vm_size" {
  type = string
}
variable "dc_dc2_host_name" {
  type = string
}
variable "dc_dc2_data_disk_size_gb" {
  type = number
}
variable "dc_dc2_data_disk_type" {
  type = string
}
variable "dc_dc2_ip_address" {
  type = string
}
variable "dc_dc2_os_disk_size_gb" {
  type = number
}
variable "dc_dc2_os_disk_type" {
  type = string
}
variable "dc_dc2_vm_name" {
  type = string
}
variable "dc_dc2_vm_size" {
  type = string
}
variable "dc_domain_name" {
  type = string
}
variable "dc_domain_netbios_name" {
  type = string
}
variable "dc_external_dns_resolver" {
  type = string
}
variable "dc_safemode_password" {
  type = string
  sensitive = true
}
variable "dc_shm_id" {
  type = string
}
variable "dc_virtual_network_name" {
  type = string
}
variable "dc_virtual_network_resource_group" {
  type = string
}
variable "dc_virtual_network_subnet" {
  type = string
}
