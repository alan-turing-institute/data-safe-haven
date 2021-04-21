resource "azurerm_resource_group" "nps" {
  name     = var.rg_name
  location = var.rg_location
}

/*
resource "azurerm_template_deployment" "nps" {
  name                = var.template_name
  resource_group_name = azurerm_resource_group.nps.name
  deployment_mode     = "Incremental"
  template_body       = file(var.template_path)
  parameters = {
    Administrator_Password         = var.administrator_password
    Administrator_User             = var.administrator_user
    BootDiagnostics_Account_Name   = var.bootdiagnostics_account_name
    Domain_Join_Password           = var.domain_join_password
    Domain_Join_User               = var.domain_join_user
    Domain_Name                    = var.domain_name
    NPS_Data_Disk_Size_GB_str      = var.data_disk_size_gb
    NPS_Data_Disk_Type             = var.data_disk_type
    NPS_Host_Name                  = var.host_name
    NPS_IP_Address                 = var.ip_address
    NPS_Os_Disk_Size_GB_str        = var.os_disk_size_gb
    NPS_Os_Disk_Type               = var.os_disk_type
    NPS_VM_Name                    = var.vm_name
    NPS_VM_Size                    = var.vm_size
    OU_Path                        = var.ou_path
    Virtual_Network_Name           = var.virtual_network_name
    Virtual_Network_Resource_Group = var.virtual_network_resource_group
    Virtual_Network_Subnet         = var.virtual_network_subnet
  }
}
*/
