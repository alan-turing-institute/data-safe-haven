variable "rg_name" {
  type = string
}
variable "rg_location" {
  type = string
}
variable "script_sa_name" {
  type = string
}
variable "boot_sa_name" {
  type = string
}
variable "art_sa_name" {
  type = string
}
variable "dc_active_directory_configuration_path" {
  type = string
}
variable "dc_createadpdc_path" {
  type = string
}
variable "dc_createadbdc_path" {
  type = string
}
variable "dc_config_files_path" {
    type = string
}
variable "dc_config_files" {
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
variable "dc_config_file_disconnect_ad" {
  type = string
}
variable "dc_chrome_source_uri" {
  type = string
  default = "http://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
}
variable "dc_putty_source_uri" {
  type = string
}
variable "nps_config_files_path" {
    type = string
}
variable "nps_config_files" {
  type = list(string)
  default = [
    "Ensure_MFA_SP_AAD.ps1", 
    "nps_config.xml"
  ]
}
