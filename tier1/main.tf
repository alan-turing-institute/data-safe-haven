# Configure the Microsoft Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
  backend "azurerm" {
      subscription_id = "813e99a0-5c7c-4c43-afd3-2a9566880854"
      resource_group_name = "RG_T1_TERRAFORM"
      storage_account_name = "terraformstorage9876"
      container_name = "terraformcontainer"
      key = "terraform.tfstate"
  }
}

# Declare Azure provider
provider "azurerm" {
  subscription_id = "813e99a0-5c7c-4c43-afd3-2a9566880854"
  features {}
}

# Create resource group
resource "azurerm_resource_group" "this" {
  for_each = var.resource_groups
  name     = "${var.const_rg}_${var.const_tier1}_${each.value}"
  location = var.location
}

# Create virtual network
resource "azurerm_virtual_network" "this" {
  name                = "${var.const_vnet}_${var.const_tier1}"
  address_space       = ["10.1.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.this["networking"].name
}

# Create subnet
resource "azurerm_subnet" "authentication" {
  name                 = "${var.resource_groups["authentication"]}_${var.const_subnet}"
  resource_group_name  = azurerm_virtual_network.this.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.1.0.0/24"]
}

# Create public IP
resource "azurerm_public_ip" "publicip" {
  name                = "${var.resource_groups["authentication"]}_${var.const_publicip}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this["authentication"].name
  allocation_method   = "Dynamic"
}

# Create Network Security Group
resource "azurerm_network_security_group" "authentication" {
  name                = "${var.resource_groups["authentication"]}_${var.const_nsg}"
  location            = var.location
  resource_group_name = azurerm_virtual_network.this.resource_group_name
}

# Create network interface
resource "azurerm_network_interface" "authentication" {
  name                = "${var.resource_groups["authentication"]}_${var.const_nic}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this["authentication"].name

  ip_configuration {
    name                          = "${var.resource_groups["authentication"]}_${var.const_nic}_${var.const_ip_config}"
    subnet_id                     = azurerm_subnet.authentication.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.0.4"
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }
}

# Associate subnet with network security group
resource "azurerm_subnet_network_security_group_association" "authentication" {
  subnet_id                 = azurerm_subnet.authentication.id
  network_security_group_id = azurerm_network_security_group.authentication.id
}


data "azurerm_key_vault_secret" "guacamole_admin_username" {
  name         = "adminusername"
  key_vault_id = var.const_keyvault_id
}

data "azurerm_key_vault_secret" "guacamole_admin_password" {
  name         = "adminpasswordguacamole"
  key_vault_id = var.const_keyvault_id
}


resource "tls_private_key" "admin" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}


data "template_file" "ansible_yaml" {
  template = file("scripts/cloud_init_ansible.yaml")
}


# Create a Linux virtual machine
resource "azurerm_linux_virtual_machine" "authentication" {
  name                  = "${var.resource_groups["authentication"]}_${var.const_vm}1"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this["authentication"].name
  network_interface_ids = [azurerm_network_interface.authentication.id]
  size                  = var.vm_size
  computer_name         = "${var.resource_groups["authentication"]}${var.const_vm}"
  
  admin_username        = data.azurerm_key_vault_secret.guacamole_admin_username.value
  admin_password        = data.azurerm_key_vault_secret.guacamole_admin_password.value
  disable_password_authentication = false

  custom_data = base64encode(data.template_file.ansible_yaml.rendered)

  os_disk {
    name                 = "OsDisk"
    caching              = "ReadWrite"
    storage_account_type = var.storage_type
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }
}

resource "azurerm_linux_virtual_machine" "authentication" {
  connection {
    type     = "ssh"
    user     = data.azurerm_key_vault_secret.guacamole_admin_username.value
    password = data.azurerm_key_vault_secret.guacamole_admin_password.value
    host     = var.azurerm_linux_virtual_machine.authentication.public_ip_address
  }
  
  provisioner "remote-exec" {
    inline = [
      "ssh-keygen"
    ]
  }
}

