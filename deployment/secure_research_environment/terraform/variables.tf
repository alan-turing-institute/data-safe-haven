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
