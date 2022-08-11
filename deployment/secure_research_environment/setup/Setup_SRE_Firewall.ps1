param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Load the SRE VNet
# -----------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg


# Load the SHM firewall and ensure it is started (it can be deallocated to save costs or if credit has run out)
# -------------------------------------------------------------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
$firewall = Start-Firewall -Name $config.shm.firewall.name -ResourceGroupName $config.shm.network.vnet.rg -VirtualNetworkName $config.shm.network.vnet.name
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Deploy a route table for this SRE
# Note that the route table must be in the same subscription as any subnets attached to it so we cannot use the one from the SHM
# ------------------------------------------------------------------------------------------------------------------------------
$routeTable = Deploy-RouteTable -Name $config.sre.firewall.routeTableName -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location


# Load all traffic rules from template
# ------------------------------------
$config.shm.firewall["privateIpAddress"] = $firewall.IpConfigurations.PrivateIpAddress
$rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" "sre-firewall-rules.json") -Parameters $config -AsHashtable
$ruleNameFilter = "sre-$($config.sre.id)*"


# Add routes to the route table
# We need to keep all routing symmetric, or it will be dropped by the firewall (see eg. https://azure.microsoft.com/en-gb/blog/accessing-virtual-machines-behind-azure-firewall-with-azure-bastion/).
# VPN gateway and Remote Desktop connections do not come via the firewall so they must return by the same route.
# All other requests should be routed via the firewall.
# Rules are applied by looking for the closest CIDR match first, so the general rule from 0.0.0.0/0 will always come last.
# ------------------------------------------------------------------------------------------------------------------------
foreach ($route in $rules.routes) {
    $null = Deploy-Route -Name $route.name -RouteTableName $config.sre.firewall.routeTableName -AppliesTo $route.properties.addressPrefix -NextHop $route.properties.nextHop
}


# Attach all non-excluded subnets to the route table that will send traffic through the firewall
# ----------------------------------------------------------------------------------------------
# The RDG and deployment subnets always have internet access
$excludedSubnetNames = @($config.sre.network.vnet.subnets.remoteDesktop.name, $config.sre.network.vnet.subnets.deployment.name)
# The compute subnet will have internet access according to what is in the config file (eg. for Tier 0 and Tier 1)
if ($config.sre.remoteDesktop.networkRules.outboundInternet -eq "Allow") {
    $excludedSubnetNames += $config.sre.network.vnet.subnets.compute.name
}
# Attach all remaining subnets to the route table
foreach ($subnet in $VirtualNetwork.Subnets) {
    if ($excludedSubnetNames.Contains($subnet.Name)) {
        Add-LogMessage -Level Info "Ensuring that $($subnet.Name) is NOT attached to any route table..."
        $VirtualNetwork = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $subnet.Name -AddressPrefix $subnet.AddressPrefix -RouteTable $null | Set-AzVirtualNetwork
    } else {
        Add-LogMessage -Level Info "Ensuring that $($subnet.Name) is attached to $($routeTable.Name)..."
        $VirtualNetwork = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $subnet.Name -AddressPrefix $subnet.AddressPrefix -RouteTable $routeTable | Set-AzVirtualNetwork
    }
}


# Set firewall rules from template
# --------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
# Application rules
foreach ($ruleCollectionName in $firewall.ApplicationRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*" } | ForEach-Object { $_.Name }) {
    $null = $firewall.RemoveApplicationRuleCollectionByName($ruleCollectionName)
    Add-LogMessage -Level Info "Removed existing '$ruleCollectionName' application rule collection."
}
if ($rules.applicationRuleCollections) {
    foreach ($ruleCollection in $rules.applicationRuleCollections) {
        Add-LogMessage -Level Info "Setting rules for application rule collection '$($ruleCollection.name)'..."
        foreach ($rule in $ruleCollection.properties.rules) {
            $params = @{}
            if ($rule.fqdnTags) { $params["TargetTag"] = $rule.fqdnTags }
            if ($rule.protocols) { $params["Protocol"] = $rule.protocols }
            if ($rule.targetFqdns) { $params["TargetFqdn"] = $rule.targetFqdns }
            $firewall = Deploy-FirewallApplicationRule -Name $rule.name -CollectionName $ruleCollection.name -Firewall $firewall -SourceAddress $rule.sourceAddresses -Priority $ruleCollection.properties.priority -ActionType $ruleCollection.properties.action.type @params -LocalChangeOnly
        }
    }
} else {
    Add-LogMessage -Level Warning "No application rules specified."
}
# Network rules
foreach ($ruleCollectionName in $firewall.NetworkRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*" } | ForEach-Object { $_.Name }) {
    $null = $firewall.RemoveNetworkRuleCollectionByName($ruleCollectionName)
    Add-LogMessage -Level Info "Removed existing '$ruleCollectionName' network rule collection."
}
if ($rules.networkRuleCollections) {
    foreach ($ruleCollection in $rules.networkRuleCollections) {
        Add-LogMessage -Level Info "Setting rules for network rule collection '$($ruleCollection.name)'..."
        foreach ($rule in $ruleCollection.properties.rules) {
            $null = Deploy-FirewallNetworkRule -Name $rule.name -CollectionName $ruleCollection.name -Firewall $firewall -SourceAddress $rule.sourceAddresses -DestinationAddress $rule.destinationAddresses -DestinationPort $rule.destinationPorts -Protocol $rule.protocols -Priority $ruleCollection.properties.priority -ActionType $ruleCollection.properties.action.type -LocalChangeOnly
        }
    }
} else {
    Add-LogMessage -Level Warning "No network rules specified."
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Update remote firewall with rule changes
# ----------------------------------------
Add-LogMessage -Level Info "[ ] Updating remote firewall with rule changes..."
try {
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
    $null = Set-AzFirewall -AzureFirewall $firewall -ErrorAction Stop
    $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Success "Updated remote firewall with rule changes."
} catch {
    Add-LogMessage -Level Fatal "Failed to update remote firewall with rule changes!" -Exception $_.Exception
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
