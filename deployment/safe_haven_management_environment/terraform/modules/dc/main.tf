resource "azurerm_resource_group" "dc" {
  name     = var.rg_name
  location = var.rg_location
}

resource "azurerm_resource_group" "dc_bootdiagnostics" {
  name     = var.rg_name_bootdiagnostics
  location = var.rg_location
}

resource "azurerm_storage_account" "dc_bootdiagnostics" {
  name                     = var.sa_name_bootdiagnostics
  resource_group_name      = azurerm_resource_group.dc_bootdiagnostics.name
  location                 = azurerm_resource_group.dc_bootdiagnostics.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
}


/*
resource "azurerm_template_deployment" "dc" {
  name                = var.template_name
  resource_group_name = azurerm_resource_group.dc.name
  deployment_mode     = "Incremental"
  template_body       = file(var.template_path)
  parameters = {
    Administrator_Password         = var.administrator_password
    Administrator_User             = var.administrator_user
    Artifacts_Location             = var.artifacts_location
    Artifacts_Location_SAS_Token   = var.artifacts_location_sas_token
    BootDiagnostics_Account_Name   = var.bootdiagnostics_account_name
    DC1_Data_Disk_Size_GB_str      = var.dc1_data_disk_size_gb
    DC1_Data_Disk_Type             = var.dc1_data_disk_type
    DC1_Host_Name                  = var.dc1_host_name
    DC1_IP_Address                 = var.dc1_ip_address
    DC1_Os_Disk_Size_GB_str        = var.dc1_os_disk_size_gb
    DC1_Os_Disk_Type               = var.dc1_os_disk_type
    DC1_VM_Name                    = var.dc1_vm_name
    DC1_VM_Size                    = var.dc1_vm_size
    DC2_Host_Name                  = var.dc2_host_name
    DC2_Data_Disk_Size_GB_str      = var.dc2_data_disk_size_gb
    DC2_Data_Disk_Type             = var.dc2_data_disk_type
    DC2_IP_Address                 = var.dc2_ip_address
    DC2_Os_Disk_Size_GB_str        = var.dc2_os_disk_size_gb
    DC2_Os_Disk_Type               = var.dc2_os_disk_type
    DC2_VM_Name                    = var.dc2_vm_name
    DC2_VM_Size                    = var.dc2_vm_size
    Domain_Name                    = var.domain_name
    Domain_NetBIOS_Name            = var.domain_netbios_name
    External_DNS_Resolver          = var.external_dns_resolver
    SafeMode_Password              = var.safemode_password
    Shm_Id                         = var.shm_id
    Virtual_Network_Name           = var.virtual_network_name
    Virtual_Network_Resource_Group = var.virtual_network_resource_group
    Virtual_Network_Subnet         = var.virtual_network_subnet
  }
}
*/