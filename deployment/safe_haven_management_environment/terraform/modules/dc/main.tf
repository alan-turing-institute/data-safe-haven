resource "azurerm_resource_group" "dc" {
    name     = var.rg_name
    location = var.rg_location
}

resource "azurerm_availability_set" "avset" {
    name                         = "AVSET-SHM-${var.shm_id}-VM-DC"
    location                     = var.rg_location
    resource_group_name          = azurerm_resource_group.dc.name
    platform_update_domain_count = 2
    platform_fault_domain_count  = 2
}

resource "azurerm_network_interface" "dc1netinter" {
    name                          = "${var.dc1_vm_name}-NIC"
    location                      = var.rg_location
    resource_group_name           = azurerm_resource_group.dc.name
    dns_servers                   = [var.dc1_ip_address, var.dc2_ip_address, var.external_dns_resolver]
    enable_ip_forwarding          = false
    enable_accelerated_networking = false

    ip_configuration {
        name                          = "ipconfig1"
        private_ip_address_version    = "IPv4"
        private_ip_address_allocation = "Static"
        private_ip_address            = var.dc1_ip_address
        primary                       = true
        subnet_id                     = var.virtual_network_subnet
    }
}

resource "azurerm_network_interface" "dc2netinter" {
    name                          = "${var.dc2_vm_name}-NIC"
    location                      = var.rg_location
    resource_group_name           = azurerm_resource_group.dc.name
    dns_servers                   = [var.dc1_ip_address, var.dc2_ip_address, var.external_dns_resolver]
    enable_ip_forwarding          = false
    enable_accelerated_networking = false

    ip_configuration {
        name                          = "ipconfig1"
        private_ip_address_version    = "IPv4"
        private_ip_address_allocation = "Static"
        private_ip_address            = var.dc2_ip_address
        primary                       = true
        subnet_id                     = var.virtual_network_subnet
    }
}

resource "azurerm_virtual_machine" "dc1vm" {
    name                  = var.dc1_vm_name
    resource_group_name   = azurerm_resource_group.dc.name
    location              = var.rg_location
    vm_size               = var.dc1_vm_size
    availability_set_id   = azurerm_availability_set.avset.id
    network_interface_ids = [azurerm_network_interface.dc1netinter.id]

    storage_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2019-Datacenter"
        version   = "latest"
    }

    storage_os_disk {
        name                      = "${var.dc1_vm_name}-OS-DISK"
        caching                   = "ReadWrite"
        create_option             = "FromImage"
        disk_size_gb              = var.dc1_os_disk_size_gb
        managed_disk_type         = var.dc1_os_disk_type
        write_accelerator_enabled = false
        os_type                   = "Windows"
    }

    storage_data_disk {
        lun                       = 0
        name                      = "${var.dc1_vm_name}-DATA-DISK"
        caching                   = "None"
        create_option             = "Empty"
        write_accelerator_enabled = false
        disk_size_gb              = var.dc1_data_disk_size_gb
        managed_disk_type         = var.dc1_data_disk_type
    }
    
    os_profile {
        computer_name  = var.dc1_host_name
        admin_username = var.administrator_user
        admin_password = var.administrator_password
    }

    os_profile_windows_config {
        provision_vm_agent        = true
        enable_automatic_upgrades = true
    }

    boot_diagnostics {
        enabled     = true
        storage_uri = "https://${var.bootdiagnostics_account_name}.blob.core.windows.net/"
    }
}

resource "azurerm_virtual_machine" "dc2vm" {
    name                  = var.dc2_vm_name
    resource_group_name   = azurerm_resource_group.dc.name
    location              = var.rg_location
    vm_size               = var.dc2_vm_size
    availability_set_id   = azurerm_availability_set.avset.id
    network_interface_ids = [azurerm_network_interface.dc2netinter.id]

    storage_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2019-Datacenter"
        version   = "latest"
    }

    storage_os_disk {
        name                      = "${var.dc2_vm_name}-OS-DISK"
        caching                   = "ReadWrite"
        create_option             = "FromImage"
        disk_size_gb              = var.dc2_os_disk_size_gb
        managed_disk_type         = var.dc2_os_disk_type
        write_accelerator_enabled = false
        os_type                   = "Windows"
    }

    storage_data_disk {
        lun                       = 0
        name                      = "${var.dc2_vm_name}-DATA-DISK"
        caching                   = "None"
        create_option             = "Empty"
        write_accelerator_enabled = false
        disk_size_gb              = var.dc2_data_disk_size_gb
        managed_disk_type         = var.dc2_data_disk_type
    }
    
    os_profile {
        computer_name  = var.dc2_host_name
        admin_username = var.administrator_user
        admin_password = var.administrator_password
    }

    os_profile_windows_config {
        provision_vm_agent        = true
        enable_automatic_upgrades = true
    }

    boot_diagnostics {
        enabled     = true
        storage_uri = "https://${var.bootdiagnostics_account_name}.blob.core.windows.net/"
    }
}

resource "azurerm_virtual_machine_extension" "dc1vmadforest" {
    name                       = "CreateADForest"
    virtual_machine_id         = azurerm_virtual_machine.dc1vm.id
    publisher                  = "Microsoft.Powershell"
    type                       = "DSC"
    type_handler_version       = "2.77"
    auto_upgrade_minor_version = true

    settings = <<SETTINGS
    {
        "WMFVersion": "latest",
        "configuration": {
            "url": "${var.artifacts_location}/shm-dsc-dc/CreateADPDC.zip",
            "script": "CreateADPDC.ps1",
            "function": "CreateADPDC"
        },
        "configurationArguments": {
            "DomainName": "${var.domain_name}",
            "DomainNetBIOSName": "${var.domain_netbios_name}"
        }
    }
    SETTINGS
    protected_settings = <<PROTECTED_SETTINGS
    {
        "configurationArguments": {
            "adminCreds": {
                "UserName": "${var.administrator_user}",
                "Password": "${var.administrator_password}"
            },
            "SafeModeAdminCreds": {
                "UserName": "${var.administrator_user}",
                "Password": "${var.safemode_password}"
            }
        },
        "configurationUrlSasToken": "${var.artifacts_location_sas_token}"
    }
    PROTECTED_SETTINGS
}

resource "azurerm_virtual_machine_extension" "dc2vmadbdc" {
    name                       = "CreateADBDC"
    virtual_machine_id         = azurerm_virtual_machine.dc2vm.id
    publisher                  = "Microsoft.Powershell"
    type                       = "DSC"
    type_handler_version       = "2.77"
    auto_upgrade_minor_version = true

    depends_on                 = [azurerm_virtual_machine_extension.dc1vmadforest]

    settings = <<SETTINGS
    {
        "WMFVersion": "latest",
        "configuration": {
            "url": "${var.artifacts_location}/shm-dsc-dc/CreateADBDC.zip",
            "script": "CreateADBDC.ps1",
            "function": "CreateADBDC"
        },
        "configurationArguments": {
            "DomainName": "${var.domain_name}",
                "DNSServer": "${var.dc1_ip_address}"
            }
        }
    SETTINGS
    protected_settings = <<PROTECTED_SETTINGS
    {
        "configurationArguments": {
            "adminCreds": {
                "UserName": "${var.administrator_user}",
                "Password": "${var.administrator_password}"
            },
            "SafeModeAdminCreds": {
                "UserName": "${var.administrator_user}",
                "Password": "${var.safemode_password}"
            }
        },
        "configurationUrlSasToken": "${var.artifacts_location_sas_token}"
    }
    PROTECTED_SETTINGS
}

resource "azurerm_virtual_machine_extension" "dc1vmbginfo" {
    name                       = "bginfo"
    virtual_machine_id         = azurerm_virtual_machine.dc1vm.id
    publisher                  = "Microsoft.Compute"
    type                       = "bginfo"
    type_handler_version       = "2.1"
    auto_upgrade_minor_version = true
}

resource "azurerm_virtual_machine_extension" "dc2vmbginfo" {
    name                       = "bginfo"
    virtual_machine_id         = azurerm_virtual_machine.dc2vm.id
    publisher                  = "Microsoft.Compute"
    type                       = "bginfo"
    type_handler_version       = "2.1"
    auto_upgrade_minor_version = true
}

resource "azurerm_virtual_machine_extension" "dc1activedirectoryconfig" {
    name                       = "ActiveDirectoryConfiguration"
    virtual_machine_id         = azurerm_virtual_machine.dc1vm.id
    publisher                  = "Microsoft.Compute"
    type                       = "CustomScriptExtension"
    type_handler_version       = "1.10"
    auto_upgrade_minor_version = true
    
    depends_on                 = [azurerm_virtual_machine_extension.dc1vmadforest]

    settings = <<SETTINGS
    {  
    }
    SETTINGS
    protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell.exe -File Active_Directory_Configuration.ps1 -domainAdminUsername ${var.administrator_user} -domainControllerVmName ${var.dc1_vm_name} -domainOuBase ${var.domain_ou_base} -gpoBackupPath ${var.gpo_backup_path_b64} -netbiosName ${var.domain_netbios_name} -shmFdqn ${var.domain_name} -securityGroupsB64 ${var.security_groups_b64} -userAccountsB64 ${var.user_accounts_b64}",
        "fileUris": ["${var.scripts_location}/shm-configuration-dc/Active_Directory_Configuration.ps1${var.scripts_location_sas_token}"]
    }
   
    PROTECTED_SETTINGS
}