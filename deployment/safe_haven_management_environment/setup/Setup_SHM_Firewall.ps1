param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Ensure that firewall subnet exists
# ----------------------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.network.vnet.name -ResourceGroupName $config.network.vnet.rg
$subnet = Deploy-Subnet -Name $config.network.subnets.firewall.name -VirtualNetwork $virtualNetwork -AddressPrefix $config.network.subnets.firewall.cidr


# Create the firewall with a public IP address
# NB. the firewall needs to be in the same resource group as the VNet
# NB. it is not possible to assign a private IP address to the firewall - it will take the first available one in the subnet
# --------------------------------------------------------------------------------------------------------------------------------
Add-LogMessage -Level Info "Create the firewall with a public IP address"
$firewall = Deploy-Firewall -Name $config.firewall.name -ResourceGroupName $config.network.vnet.rg -Location $config.location -VirtualNetworkName $config.network.vnet.name


# Save the firewall private IP address for future use
$firewallPrivateIP = $firewall.IpConfigurations.PrivateIpAddress
Add-LogMessage -Level Info "firewallPrivateIP $firewallPrivateIP"


# Create a routing table ensuring that BGP propagation is disabled
# Without this, VMs might be able to jump directly to the target without going through the firewall
# -------------------------------------------------------------------------------------------------
$routeTable = Deploy-RouteTable -Name $config.firewall.routeTableName -ResourceGroupName $config.network.vnet.rg -Location $config.location


# Add routes to the route table
# We need to keep all routing symmetric, or it will be dropped by the firewall.
# VPN gateway connections do not come via the firewall so they must return by the same route.
# All other requests should be routed via the firewall.
# Since the gateway subnet CIDR is more specific than the general rule, it will take precedence
# ---------------------------------------------------------------------------------------------
$null = Deploy-Route -Name "ViaVpn" -RouteTable $routeTable -AppliesTo $config.network.vpn.cidr -NextHop "VirtualNetworkGateway"
$null = Deploy-Route -Name "ViaFirewall" -RouteTable $routeTable -AppliesTo "0.0.0.0/0" -NextHop $firewallPrivateIP


# Attach all subnets except the VPN gateway to the firewall route table
# ---------------------------------------------------------------------
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.network.subnets.identity.name -AddressPrefix $config.network.subnets.identity.cidr -RouteTable $RouteTable | Set-AzVirtualNetwork


# Set firewall rules from template
# --------------------------------
Add-LogMessage -Level Info "Setting firewall rules from template..."
$params = @{
    FirewallName = $config.firewall.name
    FirewallPublicIpId = $firewall.IpConfigurations.PublicIpAddress.Id
    FirewallSubnetId = $subnet.Id
    Location = $config.location
    SubnetCidrIdentity = $config.network.subnets.identity.cidr
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-firewall-rules-template.json") -Params $params -ResourceGroupName $config.network.vnet.rg



# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
