param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Ensure that firewall subnet exists
# ----------------------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.network.vnet.name -ResourceGroupName $config.network.vnet.rg
$null = Deploy-Subnet -Name $config.network.vnet.subnets.firewall.name -VirtualNetwork $virtualNetwork -AddressPrefix $config.network.vnet.subnets.firewall.cidr


# Create the firewall with a public IP address
# NB. the firewall needs to be in the same resource group as the VNet
# NB. it is not possible to assign a private IP address to the firewall - it will take the first available one in the subnet
# --------------------------------------------------------------------------------------------------------------------------------
$firewall = Deploy-Firewall -Name $config.firewall.name -ResourceGroupName $config.network.vnet.rg -Location $config.location -VirtualNetworkName $config.network.vnet.name


# Enable logging for this firewall
# --------------------------------
Add-LogMessage -Level Info "Enable logging for this firewall"
$workspace = Deploy-LogAnalyticsWorkspace -Name $config.logging.workspaceName -ResourceGroupName $config.logging.rg -Location $config.location
$null = Set-AzDiagnosticSetting -ResourceId $firewall.Id -WorkspaceId $workspace.ResourceId -Enabled $true
if ($?) {
    Add-LogMessage -Level Success "Enabled logging to workspace '$($config.logging.workspaceName)'"
} else {
    Add-LogMessage -Level Fatal "Failed to enabled logging to workspace '$($config.logging.workspaceName)'!"
}


# Create a routing table ensuring that BGP propagation is disabled
# Without this, VMs might be able to jump directly to the target without going through the firewall
# -------------------------------------------------------------------------------------------------
$routeTable = Deploy-RouteTable -Name $config.firewall.routeTableName -ResourceGroupName $config.network.vnet.rg -Location $config.location


# Set firewall rules from template
# --------------------------------
$workspace = Get-AzOperationalInsightsWorkspace -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg
$workspaceId = $workspace.CustomerId
Add-LogMessage -Level Info "Setting firewall rules from template..."
$rules = (Get-Content (Join-Path $PSScriptRoot ".." "network_rules" "shm-firewall-rules.json") -Raw).
    Replace("<dc1-ip-address>", $config.dc.ip).
    Replace("<ntp-server-fqdns>", $($config.time.ntp.serverFqdns -join '", "')).  # This join relies on <ntp-server-fqdns> being wrapped in double-quotes in the template JSON file
    Replace("<shm-firewall-private-ip>", $firewall.IpConfigurations.PrivateIpAddress).
    Replace("<shm-id>", $config.id).
    Replace("<subnet-identity-cidr>", $config.network.vnet.subnets.identity.cidr).
    Replace("<subnet-repository-cidr>", $config.network.repositoryVnet.subnets.repository.cidr).
    Replace("<subnet-vpn-cidr>", $config.network.vpn.cidr).
    Replace("<logging-workspace-id>", $workspaceId) | ConvertFrom-Json -AsHashtable


# Add routes to the route table
# We need to keep all routing symmetric, or it will be dropped by the firewall (see eg. https://azure.microsoft.com/en-gb/blog/accessing-virtual-machines-behind-azure-firewall-with-azure-bastion/).
# VPN gateway connections do not come via the firewall so they must return by the same route.
# All other requests should be routed via the firewall.
# Rules are applied by looking for the closest CIDR match first, so the general rule from 0.0.0.0/0 will always come last.
# ------------------------------------------------------------------------------------------------------------------------
foreach ($route in $rules.routes) {
    $null = Deploy-Route -Name $route.name -RouteTableName $config.firewall.routeTableName -AppliesTo $route.properties.addressPrefix -NextHop $route.properties.nextHop
}


# Attach all subnets except the VPN gateway to the firewall route table
# ---------------------------------------------------------------------
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.network.vnet.subnets.identity.name -AddressPrefix $config.network.vnet.subnets.identity.cidr -RouteTable $RouteTable | Set-AzVirtualNetwork
$null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork -Name $config.network.vnet.subnets.web.name -AddressPrefix $config.network.vnet.subnets.web.cidr -RouteTable $RouteTable | Set-AzVirtualNetwork


$ruleNameFilter = "shm-$($config.id)"


# Application rules
# -----------------
foreach ($ruleCollectionName in $firewall.ApplicationRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*" } | ForEach-Object { $_.Name }) {
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
foreach ($ruleCollectionName in $firewall.NetworkRuleCollections | Where-Object { $_.Name -like "$ruleNameFilter*" } | ForEach-Object { $_.Name }) {
    $null = $firewall.RemoveNetworkRuleCollectionByName($ruleCollectionName)
    Add-LogMessage -Level Info "Removed existing '$ruleCollectionName' network rule collection."
}
Add-LogMessage -Level Info "Setting firewall network rules..."
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


# Restart primary domain controller if it is running
# --------------------------------------------------
# This ensures that it establishes a new SSPR connection through the firewall in case
# it was previously blocked due to incorrect firewall rules or a deallocated firewall
if (Confirm-AzVMRunning -Name $config.dc.vmName -ResourceGroupName $config.dc.rg) {
    Start-VM -Name $config.dc.vmName -ResourceGroupName $config.dc.rg -ForceRestart
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
