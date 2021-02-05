# Configure the Microsoft Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

# Declare Azure provider
provider "azurerm" {
  features {}
}

# Create resource group
resource "azurerm_resource_group" "this" {
  for_each = var.resource_groups
  name     = "${var.resource_tag.resource_group}"
  location = var.location
}

# Create virtual network
resource "azurerm_virtual_network" "this" {
  name                = "${var.resource_tag.virtual_network}"
  address_space       = ["10.1.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

# Create subnet
resource "azurerm_subnet" "this" {
  name                 = "${var.resource_tag.subnet}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.1.0.0/16"]
}

# Create Network Security Group
resource "azurerm_network_security_group" "this" {
  name                = "${var.resource_tag.network_security_group}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

# Associate subnet with network security group
resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# Create public IP
resource "azurerm_public_ip" "guacamole" {
  name                = "${var.resource_tag.public_ip_address}_guacamole"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Dynamic"
}

# Create network interface
resource "azurerm_network_interface" "guacamole" {
  name                = "${var.resource_tag.virtual_machine}_guacamole"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "guacamole"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.0.4"
    public_ip_address_id          = azurerm_public_ip.guacamole.id
  }
}

# Create Guacamole admin key pair
resource "tls_private_key" "guacamole_admin" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

# Write admin account private key to a file
resource "local_file" "guacamole_admin_private_key" {
  filename        = "../ansible/guacamole_admin_id_rsa.pem"
  file_permission = "0600"
  content         = tls_private_key.guacamole_admin.private_key_pem
}

# Create a Linux virtual machine
resource "azurerm_linux_virtual_machine" "authentication" {
  name                  = "${var.resource_tag.virtual_machine}_guacamole"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  network_interface_ids = [azurerm_network_interface.guacamole.id]
  size                  = var.vm_size.guacamole
  computer_name         = "${var.resource_tag.virtual_machine}_guacamole"

  admin_username        = var.admin_username.guacamole
  admin_password        = data.azurerm_key_vault_secret.guacamole_admin_password.value

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username.guacamole
    public_key = tls_private_key.guacamole_admin.public_key_openssh
  }

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
