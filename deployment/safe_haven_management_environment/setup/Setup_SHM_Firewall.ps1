param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureOperationalInsights -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Ensure that firewall subnet exists
# ----------------------------------
$vnetShm = Get-VirtualNetwork $config.network.vnet.name -ResourceGroupName $config.network.vnet.rg
$null = Deploy-Subnet -Name $config.network.vnet.subnets.firewall.name -VirtualNetwork $vnetShm -AddressPrefix $config.network.vnet.subnets.firewall.cidr


# Create the firewall with a public IP address
# NB. the firewall needs to be in the same resource group as the VNet
# NB. it is not possible to assign a private IP address to the firewall - it will take the first available one in the subnet
# --------------------------------------------------------------------------------------------------------------------------------
$firewall = Deploy-Firewall -Name $config.firewall.name -ResourceGroupName $config.network.vnet.rg -Location $config.location -VirtualNetworkName $config.network.vnet.name


# Create the logging workspace if it does not already exist
# ---------------------------------------------------------
$workspace = Deploy-LogAnalyticsWorkspace -Name $config.monitoring.loggingWorkspace.name -ResourceGroupName $config.monitoring.rg -Location $config.location


# Enable logging for this firewall
# --------------------------------
Set-LogAnalyticsDiagnostics -ResourceId $firewall.Id -ResourceName $firewall.Name -WorkspaceId $workspace.ResourceId


# Create or retrieve the route table.
# Note that we need to disable BGP propagation or VMs might be able to jump directly to the target without going through the firewall
# -----------------------------------------------------------------------------------------------------------------------------------
$routeTable = Deploy-RouteTable -Name $config.firewall.routeTableName -ResourceGroupName $config.network.vnet.rg -Location $config.location


# Set firewall rules from template
# --------------------------------
Add-LogMessage -Level Info "Setting firewall rules from template..."
$config.firewall["privateIpAddress"] = $firewall.IpConfigurations.PrivateIpAddress
$rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" "shm-firewall-rules.json") -Parameters $config -AsHashtable
$ruleNameFilter = "shm-$($config.id)"


# Add routes to the route table
# We need to keep all routing symmetric, or it will be dropped by the firewall (see eg. https://azure.microsoft.com/en-gb/blog/accessing-virtual-machines-behind-azure-firewall-with-azure-bastion/).
# VPN gateway connections do not come via the firewall so they must return by the same route.
# All other requests should be routed via the firewall.
# Rules are applied by looking for the closest CIDR match first, so the general rule from 0.0.0.0/0 will always come last.
# ------------------------------------------------------------------------------------------------------------------------
foreach ($route in $rules.routes) {
    $null = Deploy-Route -Name $route.name -RouteTableName $config.firewall.routeTableName -AppliesTo $route.properties.addressPrefix -NextHop $route.properties.nextHop
}


# Attach all subnets except the VPN gateway and firewall subnets to the firewall route table
# ------------------------------------------------------------------------------------------
$excludedSubnetNames = @($config.network.vnet.subnets.firewall.name, $config.network.vnet.subnets.gateway.name)
$vnetRepositoriesTier2 = Get-VirtualNetwork -Name $config.network.vnetRepositoriesTier2.name -ResourceGroupName $config.network.vnetRepositoriesTier2.rg
$vnetRepositoriesTier3 = Get-VirtualNetwork -Name $config.network.vnetRepositoriesTier3.name -ResourceGroupName $config.network.vnetRepositoriesTier3.rg
foreach ($vnet in @($vnetShm, $vnetRepositoriesTier2, $vnetRepositoriesTier3)) {
    foreach ($subnet in $vnet.Subnets) {
        if ($excludedSubnetNames.Contains($subnet.Name)) {
            $vnet = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnet.Name -AddressPrefix $subnet.AddressPrefix -RouteTable $null | Set-AzVirtualNetwork
        } else {
            $vnet = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnet.Name -AddressPrefix $subnet.AddressPrefix -RouteTable $routeTable | Set-AzVirtualNetwork
        }
    }
}


# Application rules
# -----------------
foreach ($ruleCollectionName in $firewall.ApplicationRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*" } | ForEach-Object { $_.Name }) {
    $null = $firewall.RemoveApplicationRuleCollectionByName($ruleCollectionName)
    Add-LogMessage -Level Info "Removed existing '$ruleCollectionName' application rule collection."
}
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
if (-not $rules.applicationRuleCollections) {
    Add-LogMessage -Level Warning "No application rules specified."
}


# Network rules
# -------------
foreach ($ruleCollectionName in $firewall.NetworkRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*" } | ForEach-Object { $_.Name }) {
    $null = $firewall.RemoveNetworkRuleCollectionByName($ruleCollectionName)
    Add-LogMessage -Level Info "Removed existing '$ruleCollectionName' network rule collection."
}
Add-LogMessage -Level Info "Setting firewall network rules..."
foreach ($ruleCollection in $rules.networkRuleCollections) {
    Add-LogMessage -Level Info "Setting rules for network rule collection '$($ruleCollection.name)'..."
    foreach ($rule in $ruleCollection.properties.rules) {
        $params = @{}
        if ($rule.protocols) {
            $params["Protocol"] = @($rule.protocols | ForEach-Object { $_.Split(":")[0] })
            $params["DestinationPort"] = @($rule.protocols | ForEach-Object { $_.Split(":")[1] })
        }
        if ($rule.targetAddresses) { $params["DestinationAddress"] = $rule.targetAddresses }
        if ($rule.targetFqdns) { $params["DestinationFqdn"] = $rule.targetFqdns }
        $null = Deploy-FirewallNetworkRule -Name $rule.name -CollectionName $ruleCollection.name -Firewall $firewall -SourceAddress $rule.sourceAddresses -Priority $ruleCollection.properties.priority -ActionType $ruleCollection.properties.action.type @params -LocalChangeOnly
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


# Restart domain controllers if they are running
# --------------------------------------------------
# This ensures that they establish a new SSPR connection through the firewall in case
# it was previously blocked due to incorrect firewall rules or a deallocated firewall
if (Confirm-VmRunning -Name $config.dc.vmName -ResourceGroupName $config.dc.rg) {
    Start-VM -Name $config.dc.vmName -ResourceGroupName $config.dc.rg -ForceRestart
}
if (Confirm-VmRunning -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg) {
    Start-VM -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg -ForceRestart
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
