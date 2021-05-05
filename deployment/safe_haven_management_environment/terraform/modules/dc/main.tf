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

resource "azurerm_virtual_machine_extension" "dc1vmadforest" {
    name                 = "${var.dc1_vm_name}/CreateADForest"
    virtual_machine_id   = azurerm_virtual_machine.dc1vm.id
    publisher            = "Microsoft.Azure.Extensions"
    type                 = "CustomScript"
    type_handler_version = "2.0"

    settings = <<SETTINGS
    {
        "commandToExecute": "hostname && uptime"
    }
    SETTINGS

}