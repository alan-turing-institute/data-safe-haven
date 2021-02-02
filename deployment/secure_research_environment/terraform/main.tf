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
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.resource_groups["authentication"]}_${var.const_nsg}"
  location            = var.location
  resource_group_name = azurerm_virtual_network.this.resource_group_name
}

# Create network interface
resource "azurerm_network_interface" "nic" {
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
