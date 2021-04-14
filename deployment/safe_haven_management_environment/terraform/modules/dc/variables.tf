variable "rg_name" {
  type = string
}

variable "rg_location" {
  type = string
}

variable "rg_name_bootdiagnostics" {
  type = string
}

variable "sa_name_bootdiagnostics" {
  type = string
}

variable "rg_name_artifacts" {
  type = string
}

variable "sa_name_artifacts" {
  type = string
}

variable "name" {
  type = string
}

variable "template_path" {
  type = string
}

variable "createadpdc_path" {
  type = string
}

variable "createadbdc_path" {
  type = string
}

variable "config_files_path" {
    type = string
}

variable "config_files" {
  type = list(string)
  default = [
    "CreateUsers.ps1", 
    "GPOs.zip",
    "Run_ADSync.ps1",
    "StartMenuLayoutModification.xml",
    "UpdateAADSyncRule.ps1",
    "user_details_template.csv"
  ]
}

variable "config_file_disconnect_ad" {
  type = string
}

variable "chrome_source_uri" {
  type = string
  default = "http://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
}

variable "putty_source_uri" {
  type = string
}

variable "administrator_password" {
  type = string
  sensitive = true
}

variable "administrator_user" {
  type = string
}

variable "artifacts_location" {
  type = string
}

variable "artifacts_location_sas_token" {
  type = string
  sensitive = true
}

variable "bootdiagnostics_account_name" {
  type = string
}

variable "dc1_data_disk_size_gb" {
  type = number
}

variable "dc1_data_disk_type" {
  type = string
}

variable "dc1_host_name" {
  type = string
}

variable "dc1_ip_address" {
  type = string
}

variable "dc1_os_disk_size_gb" {
  type = number
}

variable "dc1_os_disk_type" {
  type = string
}

variable "dc1_vm_name" {
  type = string
}

variable "dc1_vm_size" {
  type = string
}

variable "dc2_host_name" {
  type = string
}

variable "dc2_data_disk_size_gb" {
  type = number
}

variable "dc2_data_disk_type" {
  type = string
}

variable "dc2_ip_address" {
  type = string
}

variable "dc2_os_disk_size_gb" {
  type = number
}

variable "dc2_os_disk_type" {
  type = string
}

variable "dc2_vm_name" {
  type = string
}

variable "dc2_vm_size" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "domain_netbios_name" {
  type = string
}

variable "external_dns_resolver" {
  type = string
}

variable "safemode_password" {
  type = string
  sensitive = true
}

variable "shm_id" {
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