resource "azurerm_resource_group" "nps" {
  name     = var.rg_name
  location = var.rg_location
}

resource "azurerm_network_interface" "npsnic" {
    name                          = "${var.vm_name}-NIC"
    location                      = var.rg_location
    resource_group_name           = azurerm_resource_group.nps.name
    dns_servers                   = []
    enable_ip_forwarding          = false
    enable_accelerated_networking = false

    ip_configuration {
        name                          = "ipconfig1"
        private_ip_address_version    = "IPv4"
        private_ip_address_allocation = "Static"
        private_ip_address            = var.ip_address
        primary                       = true
        subnet_id                     = var.virtual_network_subnet
    }
}

resource "azurerm_virtual_machine" "npsvm" {
    name                  = var.vm_name
    resource_group_name   = azurerm_resource_group.nps.name
    location              = var.rg_location
    vm_size               = var.vm_size
                      
    network_interface_ids = [azurerm_network_interface.npsnic.id]

    storage_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2019-Datacenter"
        version   = "latest"
    }

    storage_os_disk {
        name                      = "${var.vm_name}-OS-DISK"
        caching                   = "ReadWrite"
        create_option             = "FromImage"
        disk_size_gb              = var.os_disk_size_gb
        managed_disk_type         = var.os_disk_type
        write_accelerator_enabled = false
        os_type                   = "Windows"
    }

    storage_data_disk {
        lun                       = 0
        name                      = "${var.vm_name}-DATA-DISK"
        caching                   = "None"
        create_option             = "Empty"
        write_accelerator_enabled = false
        disk_size_gb              = var.data_disk_size_gb
        managed_disk_type         = var.data_disk_type
    }
                                
    os_profile {
        computer_name  = var.host_name
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

resource "azurerm_virtual_machine_extension" "npsvmbginfo" {
    name                       = "bginfo"
    virtual_machine_id         = azurerm_virtual_machine.npsvm.id
    publisher                  = "Microsoft.Compute"
    type                       = "bginfo"
    type_handler_version       = "2.1"
    auto_upgrade_minor_version = true
}

resource "azurerm_virtual_machine_extension" "npsvmjoindomain" {
    name                       = "joindomain"
    virtual_machine_id         = azurerm_virtual_machine.npsvm.id
    publisher                  = "Microsoft.Compute"
    type                       = "JsonADDomainExtension"
    type_handler_version       = "1.3"
    auto_upgrade_minor_version = true

    settings = <<SETTINGS
    {
        "Name": "${var.domain_name}",
        "OUPath": "${var.ou_path}",
        "User": "${var.domain_name}\\${var.domain_join_user}",
        "Restart": "true",
        "Options": "3"
    }
    SETTINGS
    protected_settings = <<PROTECTED_SETTINGS
    {
       "Password": "${var.domain_join_password}"
    }
    PROTECTED_SETTINGS
}
