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
  name     = local.resource_tag.resource_group
  location = var.location
}

# Create virtual network
resource "azurerm_virtual_network" "this" {
  name                = local.resource_tag.virtual_network
  address_space       = ["10.1.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

# Create subnet
resource "azurerm_subnet" "this" {
  name                 = local.resource_tag.subnet
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.1.0.0/16"]
}

# Create Network Security Group
resource "azurerm_network_security_group" "this" {
  name                = local.resource_tag.network_security_group
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

# Create SSH NSG rule
resource "azurerm_network_security_rule" "ssh" {
  name                        = "SSH"
  priority                    = 1001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this.name
}

# Create HTTP 8080 NSG rule
resource "azurerm_network_security_rule" "guacamole" {
  name                        = "GUACAMOLEHTTP"
  priority                    = 1002
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this.name
}

# Associate subnet with network security group
resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# Create public IP
resource "azurerm_public_ip" "guacamole" {
  name                = "${local.resource_tag.public_ip}_guacamole"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Dynamic"
}

# Register public IP address to write to Ansible inventory
# (Azure does not assign public IPs until the IP object is attached to a
# resource, hence the dependency on the virtual machine)
data "azurerm_public_ip" "guacamole" {
  name                = azurerm_public_ip.guacamole.name
  resource_group_name = azurerm_resource_group.this.name
  depends_on          = [azurerm_linux_virtual_machine.guacamole]
}

# Create network interface
resource "azurerm_network_interface" "guacamole" {
  name                = "${local.resource_tag.network_interface}_guacamole"
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
resource "azurerm_linux_virtual_machine" "guacamole" {
  name                  = "${local.resource_tag.virtual_machine}_guacamole"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  network_interface_ids = [azurerm_network_interface.guacamole.id]
  size                  = var.vm_size.guacamole
  computer_name         = "guacamole"
  admin_username        = var.admin_username.guacamole

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

# Create DNS zone
resource "azurerm_dns_zone" "this" {
  name                = var.domain
  resource_group_name = azurerm_resource_group.this.name
}

# Create A record for Guacamole
resource "azurerm_dns_a_record" "login" {
  name                = "login"
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.guacamole.id
}

# Write Ansible inventory
resource "local_file" "ansible_inventory" {
  filename        = "../ansible/inventory.yaml"
  file_permission = "0644"
  content         = <<-DOC
    ---
    all:
      hosts:
        guacamole:
          ansible_host: ${data.azurerm_public_ip.guacamole.ip_address}
          ansible_user: ${var.admin_username.guacamole}
          ansible_ssh_private_key_file: ${local_file.guacamole_admin_private_key.filename}
    DOC
}

# Write variables for Ansible to access
resource "local_file" "terraform_vars" {
  filename = "../ansible/terraform_vars.yaml"
  file_permission = "0644"
  content         = <<-DOC
    ---
    domain: ${var.domain}
    DOC
}
