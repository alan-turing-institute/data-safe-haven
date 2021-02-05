variable "location" {
  type    = string
  default = "uksouth"
}

variable "const_rg" {
  type    = string
  default = "RG"
}

variable "const_tier1" {
  type    = string
  default = "T1"
}

variable "const_vnet" {
  type    = string
  default = "VNET"
}

variable "const_subnet" {
  type    = string
  default = "SUBNET"
}

variable "const_publicip" {
  type    = string
  default = "PUBLICIP"
}

variable "const_nsg" {
  type    = string
  default = "NSG"
}

variable "const_nic" {
  type    = string
  default = "NIC"
}

variable "const_ip_config" {
  type    = string
  default = "IPCONFIG"
}

variable "const_vm" {
  type    = string
  default = "VM"
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "admin_username" {
  type    = string
  default = "authelia_admin"
}

variable "resource_groups" {
  type = object({
    authentication = string
    remote_desktop = string
    compute        = string
    networking     = string
  })
  default = {
    authentication = "AUTH"
    remote_desktop = "REMOTEDESK"
    compute        = "COMPUTE"
    networking     = "NETWORKING"
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


# CHAGE ALL BEHIND THIS POINT

variable "const_keyvault_id" {
  type    = string
  default = "/subscriptions/813e99a0-5c7c-4c43-afd3-2a9566880854/resourceGroups/RG_T1_TERRAFORM/providers/Microsoft.KeyVault/vaults/TERRAFFORMKEYVAULT"
  sensitive   = true
}