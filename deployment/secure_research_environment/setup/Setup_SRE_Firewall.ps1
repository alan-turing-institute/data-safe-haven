param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Load the SRE VNet and gateway IP
# --------------------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
# $rdsGatewayPublicIp = (Get-AzPublicIpAddress -ResourceGroupName $config.sre.rds.rg | Where-Object { $_.Name -match "$($config.sre.rds.gateway.vmName).*" } | Select-Object -First 1).IpAddress


# Load the SHM firewall
# ---------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
# Ensure Firewall is started (it can be deallocated to save costs or if credit has run out)
$firewall = Start-Firewall -Name $config.shm.firewall.name -ResourceGroupName $config.shm.network.vnet.rg -VirtualNetworkName $config.shm.network.vnet.name
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Deploy a route table for this SRE
# Note that the route table must be in the same subscription as any subnets attached to it so we cannot use the one from the SHM
# ------------------------------------------------------------------------------------------------------------------------------
$routeTable = Deploy-RouteTable -Name $config.sre.firewall.routeTableName -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location


# Load all traffic rules from template
# ------------------------------------
$rules = (Get-Content (Join-Path $PSScriptRoot ".." "network_rules" "sre-firewall-rules.json") -Raw).
    Replace("<shm-firewall-private-ip>", $firewall.IpConfigurations.PrivateIpAddress).
    Replace("<subnet-shm-vpn-cidr>", $config.shm.network.vpn.cidr) | ConvertFrom-Json -AsHashtable


# Add routes to the route table
# We need to keep all routing symmetric, or it will be dropped by the firewall (see eg. https://azure.microsoft.com/en-gb/blog/accessing-virtual-machines-behind-azure-firewall-with-azure-bastion/).
# VPN gateway and Remote Desktop connections do not come via the firewall so they must return by the same route.
# All other requests should be routed via the firewall.
# Rules are applied by looking for the closest CIDR match first, so the general rule from 0.0.0.0/0 will always come last.
# ------------------------------------------------------------------------------------------------------------------------
foreach ($route in $rules.routes) {
    $null = Deploy-Route -Name $route.name -RouteTableName $config.sre.firewall.routeTableName -AppliesTo $route.properties.addressPrefix -NextHop $route.properties.nextHop
}


# Attach all subnets except the RDG subnet to the firewall route table
# --------------------------------------------------------------------
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.vnet.subnets.compute.name -AddressPrefix $config.sre.network.vnet.subnets.compute.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.vnet.subnets.databases.name -AddressPrefix $config.sre.network.vnet.subnets.databases.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.vnet.subnets.deployment.name -AddressPrefix $config.sre.network.vnet.subnets.deployment.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.vnet.subnets.identity.name -AddressPrefix $config.sre.network.vnet.subnets.identity.cidr -RouteTable $routeTable | Set-AzVirtualNetwork


# Set firewall rules from template
# --------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName


$ruleNameFilter = "sre-$($config.sre.id)*"
# Application rules
# -----------------
foreach ($ruleCollectionName in $firewall.ApplicationRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*"} | ForEach-Object { $_.Name }) {
    $null = $firewall.RemoveApplicationRuleCollectionByName($ruleCollectionName)
    Add-LogMessage -Level Info "Removed existing '$ruleCollectionName' application rule collection."
}
foreach ($ruleCollection in $rules.applicationRuleCollections) {
    Add-LogMessage -Level Info "Setting rules for application rule collection '$($ruleCollection.Name)'..."
    foreach ($rule in $ruleCollection.properties.rules) {
        $params = @{}
        if ($rule.fqdnTags) { $params["TargetTag"] = $rule.fqdnTags }
        if ($rule.protocols) { $params["Protocol"] = $rule.protocols }
        if ($rule.targetFqdns) { $params["TargetFqdn"] = $rule.targetFqdns }
        $firewall = Deploy-FirewallApplicationRule -Name $rule.name -CollectionName $ruleCollection.name -Firewall $firewall -SourceAddress $rule.sourceAddresses -Priority $ruleCollection.properties.priority -ActionType $ruleCollection.properties.action.type @params -LocalChangeOnly
    }
}
if (-not $rules.applicationRuleCollections) {
    Add-LogMessage -Level Warning "No application rules specified."
}


# Network rules
# -------------
foreach ($ruleCollectionName in $firewall.NetworkRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*"} | ForEach-Object { $_.Name }) {
    $null = $firewall.RemoveNetworkRuleCollectionByName($ruleCollectionName)
    Add-LogMessage -Level Info "Removed existing '$ruleCollectionName' network rule collection."
}
foreach ($ruleCollection in $rules.networkRuleCollections) {
    Add-LogMessage -Level Info "Setting rules for network rule collection '$($ruleCollection.Name)'..."
    foreach ($rule in $ruleCollection.properties.rules) {
        $null = Deploy-FirewallNetworkRule -Name $rule.name -CollectionName $ruleCollection.name -Firewall $firewall -SourceAddress $rule.sourceAddresses -DestinationAddress $rule.destinationAddresses -DestinationPort $rule.destinationPorts -Protocol $rule.protocols -Priority $ruleCollection.properties.priority -ActionType $ruleCollection.properties.action.type -LocalChangeOnly
    }
}
if (-not $rules.networkRuleCollections) {
    Add-LogMessage -Level Warning "No network rules specified."
}


# Update remote firewall with rule changes
# ----------------------------------------
Add-LogMessage -Level Info "[ ] Updating remote firewall with rule changes..."
$firewall = Set-AzFirewall -AzureFirewall $firewall -ErrorAction Stop
Add-LogMessage -Level Success "Updated remote firewall with rule changes."


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
