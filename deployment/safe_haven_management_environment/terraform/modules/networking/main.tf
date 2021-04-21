resource "azurerm_resource_group" "net" {
    name     = var.rg_name
    location = var.rg_location
}

resource "azurerm_network_security_group" "net" {
    name                = var.nsg_identity_name
    location            = var.rg_location
    resource_group_name = azurerm_resource_group.net.name
}

resource "azurerm_network_security_rule" "rpc_endpoint_mapper" {
    name                         = "RPC_endpoint_mapper"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "135"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 200
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "ldap" {
    name                         = "LDAP"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "389"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 201
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "ldap_ping" {
    name                         = "LDAP_Ping"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "Udp"
    source_port_range            = "*"
    destination_port_range       = "389"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 202
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "ldap_over_ssl" {
    name                         = "LDAP_over_SSL"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "636"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 203
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "global_catalog_ldap" {
    name                         = "Global_catalog_LDAP"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "3268"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 204
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "global_catalog_ldap_over_ssl" {
    name                         = "Global_catalog_LDAP_over_SSL"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "3269"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 205
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "dns" {
    name                         = "DNS"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "53"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 206
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "kerberos" {
    name                         = "Kerberos"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "88"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 207
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "smb_over_ip_microsoft_ds" {
    name                         = "SMB_over_IP_Microsoft-DS"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "445"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 208
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "netbios_service" {
    name                         = "NetBIOS_service"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "137"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 209
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "netbios_datagram_service" {
    name                         = "NetBIOS_datagram_service"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "Udp"
    source_port_range            = "*"
    destination_port_range       = "138"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 210
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "netbios_session_service" {
    name                         = "NetBIOS_session_service"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Rule"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "139"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 211
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "rpc_for_lsa_sam_netlogon" {
    name                         = "RPC_for_LSA_SAM_Netlogon"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Dynamic client ports for RPC"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "49152-65535"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 212
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "kerberos_password_change" {
    name                         = "Kerberos_Password_Change"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Kerberos Password Change"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "464"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 213
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "active_directory_web_services" {
    name                         = "Active_Directory_Web_Services"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Active Directory Web Services"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "9389"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 214
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "outboundallowntp" {
    name                         = "OutboundAllowNTP"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Outbound allow connections to NTP servers"
    protocol                     = "Udp"
    source_port_range            = "*"
    destination_port_range       = "123"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = ""
    access                       = "Allow"
    priority                     = 215
    direction                    = "Outbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = var.ipaddresses_externalntp
}

resource "azurerm_network_security_rule" "radius_authentication_rds_to_nps" {
    name                         = "RADIUS_Authentication_RDS_to_NPS"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Allows RDS servers to connection to NPS server for MFA"
    protocol                     = "Udp"
    source_port_range            = "*"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 300
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = ["1645", "1646", "1812", "1813"]
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "remote_desktop_connection" {
    name                         = "Remote_Desktop_Connection"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Allows RDP connection to servers from P2S VPN"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "3389"
    source_address_prefix        = var.vpn_cidr
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 400
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "deny_all" {
    name                         = "Deny_All"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Block non-AD traffic"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "*"
    destination_address_prefix   = "*"
    access                       = "Deny"
    priority                     = 3000
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "allowvnetinbound" {
    name                         = "AllowVnetInBound"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Allow inbound traffic from all VMs in VNET"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 65000
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "allowazureloadbalancerinbound" {
    name                         = "AllowAzureLoadBalancerInBound"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Allow inbound traffic from azure load balancer"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "AzureLoadBalancer"
    destination_address_prefix   = "*"
    access                       = "Allow"
    priority                     = 65001
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "denyallinbound" {
    name                         = "DenyAllInBound"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Deny all inbound traffic"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "*"
    destination_address_prefix   = "*"
    access                       = "Deny"
    priority                     = 65500
    direction                    = "Inbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "allowvnetoutbound" {
    name                         = "AllowVnetOutBound"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Allow outbound traffic from all VMs to all VMs in VNET"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "VirtualNetwork"
    destination_address_prefix   = "VirtualNetwork"
    access                       = "Allow"
    priority                     = 65000
    direction                    = "Outbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "allowinternetoutbound" {
    name                         = "AllowInternetOutBound"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Allow outbound traffic from all VMs to Internet"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "*"
    destination_address_prefix   = "Internet"
    access                       = "Allow"
    priority                     = 65001
    direction                    = "Outbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_network_security_rule" "denyalloutbound" {
    name                         = "DenyAllOutBound"
    resource_group_name          = azurerm_resource_group.net.name
    network_security_group_name  = azurerm_network_security_group.net.name
    description                  = "Deny all outbound traffic"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "*"
    destination_address_prefix   = "*"
    access                       = "Deny"
    priority                     = 65500
    direction                    = "Outbound"
    source_port_ranges           = []
    destination_port_ranges      = []
    source_address_prefixes      = []
    destination_address_prefixes = []
}

resource "azurerm_public_ip" "gw_pip" {
    name                    = "${var.virtual_network_name}_GW_PIP"
    resource_group_name     = azurerm_resource_group.net.name
    location                = var.rg_location
    sku                     = "Basic"
    allocation_method       = "Dynamic"
    ip_version              = "IPv4"
    idle_timeout_in_minutes = 4
}

resource "azurerm_virtual_network" "vnet" {
    name                    = var.virtual_network_name
    resource_group_name     = azurerm_resource_group.net.name
    address_space           = [var.vnet_cidr]
    location                = var.rg_location
    dns_servers             = [var.vnet_dns_dc1, var.vnet_dns_dc2]
    vm_protection_enabled   = false

    ddos_protection_plan {
        enable = false
    }

    subnet {
        name           = var.subnet_firewall_name
        address_prefix = var.subnet_firewall_cidr
    }

    subnet {
        name           = var.subnet_gateway_name
        address_prefix = var.subnet_gateway_cidr
    }

    subnet {
        name           = var.subnet_identity_name
        address_prefix = var.subnet_identity_cidr
        security_group = azurerm_network_security_group.net.id
    }
}


resource "azurerm_subnet" "subnet_firewall" {
    name                 = "${var.virtual_network_name}/${var.subnet_firewall_name}"
    resource_group_name  = azurerm_resource_group.net.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = [var.subnet_firewall_cidr]
}


resource "azurerm_subnet" "subnet_gateway" {
    name                 = "${var.virtual_network_name}/${var.subnet_gateway_name}"
    resource_group_name  = azurerm_resource_group.net.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = [var.subnet_gateway_cidr]
}

/*
resource "azurerm_subnet" "subnet_identity" {
    name                 = "${var.virtual_network_name}/${var.subnet_identity_name}"
    resource_group_name  = azurerm_resource_group.net.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = [var.subnet_identity_cidr]

    ????? 
      "networkSecurityGroup": {
                                "id": "[resourceId('Microsoft.Network/networkSecurityGroups', parameters('NSG_Identity_Name'))]"
                            },
}
*/



resource "azurerm_virtual_network_gateway" "gw" {
    name                = "${var.virtual_network_name}_GW"
    resource_group_name = azurerm_resource_group.net.name
    location            = var.rg_location
    type                = "Vpn"
    vpn_type            = "RouteBased"
    enable_bgp          = false
    active_active       = false
    sku                 = "VpnGw1"

    ip_configuration {
        name                          = "shmgwipconf"
        public_ip_address_id          = azurerm_public_ip.gw_pip.id
        private_ip_address_allocation = "Dynamic"
        subnet_id                     = azurerm_subnet.subnet_gateway.id
    }
    
    vpn_client_configuration {
        address_space        = [var.vpn_cidr]
        vpn_client_protocols = ["IkeV2", "SSTP"]
        root_certificate {
            name             = "SafeHavenManagementP2SRootCert"
            public_cert_data = 

        }
    }
}

/*
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
*/
