variable "location" {
  type        = string
  default     = "uksouth"
}

variable "sre_name" {
  type = string
}

variable "domain" {
  type = string
}

locals {
    resource_tag = {
      resource_group         = "RG_${var.sre_name}"
      virtual_network        = "VNET_${var.sre_name}"
      subnet                 = "SUBNET_${var.sre_name}"
      public_ip              = "PUBIP_${var.sre_name}"
      network_security_group = "NSG_${var.sre_name}"
      network_interface      = "NIC_${var.sre_name}"
      virtual_machine        = "VM_${var.sre_name}"
    }
}

variable "vm_size" {
  type    = map(string)
  default = {
    guacamole = "Standard_B2s"
  }
}

variable "admin_username" {
  type = map(string)
  default = {
    guacamole = "guacamole_admin"
  }
}

variable "storage_type" {
  type    = string
  default = "StandardSSD_LRS"
  validation {
    condition     = can(contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.storage_type))
    error_message = "The storage type must be one of Standard_LRS, StandardSSD_LRS and Premium_LRS."
  }
}

variable "vm_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
}
