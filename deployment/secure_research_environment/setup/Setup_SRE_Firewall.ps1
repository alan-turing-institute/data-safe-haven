param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Load the SRE VNet and gateway IP
# --------------------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
$rdsGatewayPublicIp = (Get-AzPublicIpAddress -ResourceGroupName $config.sre.rds.rg | Where-Object { $_.Name -match "$($config.sre.rds.gateway.vmName).*" } | Select-Object -First 1).IpAddress


# Load the SHM firewall
# ---------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$firewall = Get-AzFirewall -Name $config.shm.firewall.name -ResourceGroupName $config.shm.network.vnet.rg
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Deploy a route table for this SRE
# Note that the route table must be in the same subscription as any subnets attached to it so we cannot use the one from the SHM
# ------------------------------------------------------------------------------------------------------------------------------
$routeTable = Deploy-RouteTable -Name $config.sre.firewall.routeTableName -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location


# Load all traffic rules from template
# ------------------------------------
$rules = (Get-Content (Join-Path $PSScriptRoot ".." "network_rules" "sre-firewall-rules.json") -Raw).
    Replace("<priority-allow>", (5000 + ($config.sre.network.vnet.cidr).Split(".")[1])).
    Replace("<priority-deny>", (6000 + ($config.sre.network.vnet.cidr).Split(".")[1])).
    Replace("<sre-id>", $config.sre.id).
    Replace("<shm-firewall-private-ip>", $firewall.IpConfigurations.PrivateIpAddress).
    Replace("<sre-rdg-public-ip-cidr>", "${rdsGatewayPublicIp}/32").
    Replace("<subnet-shm-vpn-cidr>", $config.shm.network.vpn.cidr).
    Replace("<subnet-data-cidr>", $config.sre.network.vnet.subnets.data.cidr).
    Replace("<subnet-databases-cidr>", $config.sre.network.vnet.subnets.databases.cidr).
    Replace("<subnet-identity-cidr>", $config.sre.network.vnet.subnets.identity.cidr).
    Replace("<subnet-rds-cidr>", $config.sre.network.vnet.subnets.rds.cidr).
    Replace("<vnet-shm-cidr>", $config.shm.network.vnet.cidr) | ConvertFrom-Json -AsHashtable


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
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.vnet.subnets.data.name -AddressPrefix $config.sre.network.vnet.subnets.data.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.sre.network.vnet.subnets.databases.name -AddressPrefix $config.sre.network.vnet.subnets.databases.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
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
Add-LogMessage -Level Info "Setting firewall application rules..."
foreach ($ruleCollection in $rules.applicationRuleCollections) {
    foreach ($rule in $ruleCollection.properties.rules) {
        $params = @{}
        if ($rule.fqdnTags) { $params["TargetTag"] = $rule.fqdnTags }
        if ($rule.protocols) { $params["Protocol"] = $rule.protocols }
        if ($rule.targetFqdns) { $params["TargetFqdn"] = $rule.targetFqdns }
        $firewall = Deploy-FirewallApplicationRule -Name $rule.name -CollectionName $ruleCollection.name -Firewall $firewall -SourceAddress $rule.sourceAddresses -Priority $ruleCollection.properties.priority -ActionType $ruleCollection.properties.action.type @params -LocalChangeOnly
    }
}


# Network rules
# -------------
Add-LogMessage -Level Info "Setting firewall network rules..."
foreach ($ruleCollectionName in $firewall.NetworkRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*"} | ForEach-Object { $_.Name }) {
    $null = $firewall.RemoveNetworkRuleCollectionByName($ruleCollectionName)
    Add-LogMessage -Level Info "Removed existing '$ruleCollectionName' network rule collection."
}
Add-LogMessage -Level Info "Setting firewall network rules..."
foreach ($ruleCollection in $rules.networkRuleCollections) {
    foreach ($rule in $ruleCollection.properties.rules) {
        $null = Deploy-FirewallNetworkRule -Name $rule.name -CollectionName $ruleCollection.name -Firewall $firewall -SourceAddress $rule.sourceAddresses -DestinationAddress $rule.destinationAddresses -DestinationPort $rule.destinationPorts -Protocol $rule.protocols -Priority $ruleCollection.properties.priority -ActionType $ruleCollection.properties.action.type -LocalChangeOnly
    }
}


# Update remote firewall with rule changes
# ----------------------------------------
Add-LogMessage -Level Info "[ ] Updating remote firewall with rule changes..."
$firewall = Set-AzFirewall -AzureFirewall $firewall -ErrorAction Stop
Add-LogMessage -Level Success "Updated remote firewall with rule changes."



# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
