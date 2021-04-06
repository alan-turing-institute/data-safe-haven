resource "azurerm_resource_group" "net" {
  name     = var.rg_name
  location = var.rg_location
}

resource "azurerm_template_deployment" "shm-vnet" {
  name                = var.name
  resource_group_name = azurerm_resource_group.net.name
  deployment_mode     = "Incremental"
  template_body       = file(var.template_path)
  parameters = {
    IPAddresses_ExternalNTP_list = "${join(",", var.ipaddresses_externalntp)}"
    NSG_Identity_Name       = var.nsg_identity_name
    P2S_VPN_Certificate     = var.p2s_vpn_certificate
    Shm_Id                  = var.shm_id
    Subnet_Firewall_CIDR    = var.subnet_firewall_cidr
    Subnet_Firewall_Name    = var.subnet_firewall_name
    Subnet_Gateway_CIDR     = var.subnet_gateway_cidr
    Subnet_Gateway_Name     = var.subnet_gateway_name
    Subnet_Identity_CIDR    = var.subnet_identity_cidr
    Subnet_Identity_Name    = var.subnet_identity_name
    Virtual_Network_Name    = var.virtual_network_name
    VNET_CIDR               = var.vnet_cidr
    VNET_DNS_DC1            = var.vnet_dns_dc1
    VNET_DNS_DC2            = var.vnet_dns_dc2
    VPN_CIDR                = var.vpn_cidr
  }
}
