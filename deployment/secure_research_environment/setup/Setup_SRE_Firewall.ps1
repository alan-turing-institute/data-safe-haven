param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Load the SRE VNet and SHM firewall
# ----------------------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$firewall = Get-AzFirewall -Name $config.shm.firewall.name -ResourceGroupName $config.shm.network.vnet.rg
$firewallPrivateIP = $firewall.IpConfigurations.PrivateIpAddress
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Deploy a route table for this SRE
# Note that the route table must be in the same subscription as any subnets attached to it so we cannot use the one from the SHM
# ------------------------------------------------------------------------------------------------------------------------------
$routeTable = Deploy-RouteTable -Name $config.sre.firewall.routeTableName -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location


# Add routes to the route table
# We need to keep all routing symmetric, or it will be dropped by the firewall.
# VPN gateway connections do not come via the firewall so they must return by the same route.
# All other requests should be routed via the firewall.
# Since the gateway subnet CIDR is more specific than the general rule, it will take precedence
# ---------------------------------------------------------------------------------------------
$null = Deploy-Route -Name "ViaVpn" -RouteTable $routeTable -AppliesTo $config.shm.network.vpn.cidr -NextHop "VirtualNetworkGateway"
$null = Deploy-Route -Name "ViaFirewall" -RouteTable $routeTable -AppliesTo "0.0.0.0/0" -NextHop $firewallPrivateIP


# Attach all subnets to the firewall route table
# ----------------------------------------------
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.subnets.data.name -AddressPrefix $config.sre.network.subnets.data.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.subnets.databases.name -AddressPrefix $config.sre.network.subnets.databases.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.subnets.identity.name -AddressPrefix $config.sre.network.subnets.identity.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.subnets.rds.name -AddressPrefix $config.sre.network.subnets.rds.cidr -RouteTable $routeTable | Set-AzVirtualNetwork


# Set firewall rules from template
# --------------------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName


Add-LogMessage -Level Info "Setting firewall rules from template..."
$params = @{
    FirewallName = $firewall.Name
    FirewallPublicIpId = $firewall.IpConfigurations.PublicIpAddress.Id
    FirewallSubnetId = $firewall.IpConfigurations.Subnet.Id
    Location = $config.shm.location
    Priority = (2000 + ($config.sre.network.vnet.cidr).Split(".")[1])
    SreId = $config.sre.id
    SubnetCidrData = $config.sre.network.subnets.data.cidr
    SubnetCidrDatabases = $config.sre.network.subnets.databases.cidr
    SubnetCidrIdentity = $config.sre.network.subnets.identity.cidr
    SubnetCidrRds = $config.sre.network.subnets.rds.cidr
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-firewall-rules-template.json") -Params $params -ResourceGroupName $config.shm.network.vnet.rg
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
