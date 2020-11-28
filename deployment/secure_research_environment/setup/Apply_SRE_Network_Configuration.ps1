param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Mirrors -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Get common parameters
# ---------------------
$allowedSources = ($config.sre.rds.gateway.networkRules.allowedSources.Split(',') | ForEach-Object { $_.Trim() })  # NB. Use an array, splitting on commas and trimming any whitespace from each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$outboundInternetAccessRuleName = "$($config.sre.rds.gateway.networkRules.outboundInternet)InternetOutbound"
$nsgs = @{}


# Ensure VMs are bound to correct NSGs
# ------------------------------------
Add-LogMessage -Level Info "Applying network configuration for SRE '$($config.sre.id)' (Tier $($config.sre.tier)), hosted on subscription '$($config.sre.subscriptionName)'"


# Tier-1 and below have single NSG
# --------------------------------
if (@(0, 1).Contains([int]$config.sre.tier)) {
    $nsgs["compute"] = Get-AzNetworkSecurityGroup -Name $config.sre.network.vnet.subnets.compute.nsg.name -ResourceGroupName $config.sre.network.vnet.rg

    Add-LogMessage -Level Info "Setting inbound connection rules on user-facing NSG..."
    $null = Update-NetworkSecurityGroupRule -Name "InboundSSHAccess" -NetworkSecurityGroup $nsgs["compute"] -SourceAddressPrefix $allowedSources

    Add-LogMessage -Level Info "Setting outbound connection rules on user-facing NSG..."
    $null = Update-NetworkSecurityGroupRule -Name $outboundInternetAccessRuleName -NetworkSecurityGroup $nsgs["compute"] -Access $config.sre.rds.gateway.networkRules.outboundInternet


# Tier-2 and above have several NSGs
# ----------------------------------
} else {
    # RDS gateway
    Add-LogMessage -Level Info "Ensure RDS gateway is bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.rds.gateway.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.gateway.nsg.name -NsgResourceGroupName $config.sre.network.vnet.rg
    $nsgs["gateway"] = Get-AzNetworkSecurityGroup -Name $config.sre.rds.gateway.nsg.name -ResourceGroupName $config.sre.network.vnet.rg

    # RDS sesssion hosts
    Add-LogMessage -Level Info "Ensure RDS session hosts are bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.rds.appSessionHost.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.appSessionHost.nsg.name -NsgResourceGroupName $config.sre.network.vnet.rg
    $nsgs["sessionhosts"] = Get-AzNetworkSecurityGroup -Name $config.sre.rds.appSessionHost.nsg.name -ResourceGroupName $config.sre.network.vnet.rg

    # Data server
    Add-LogMessage -Level Info "Ensure data server is bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.dataserver.vmName -VmResourceGroupName $config.sre.dataserver.rg -NSGName $config.sre.dataserver.nsg -NsgResourceGroupName $config.sre.network.vnet.rg -WarnOnFailure
    $nsgs["dataserver"] = Get-AzNetworkSecurityGroup -Name $config.sre.dataserver.nsg -ResourceGroupName $config.sre.network.vnet.rg

    # Database servers
    Add-LogMessage -Level Info "Ensure database servers are bound to correct NSG..."
    $databaseSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.databases.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
    $nsgs["databases"] = Get-AzNetworkSecurityGroup -Name $config.sre.network.vnet.subnets.databases.nsg.name -ResourceGroupName $config.sre.network.vnet.rg
    $databaseSubnet = Set-SubnetNetworkSecurityGroup -Subnet $databaseSubnet -NetworkSecurityGroup $nsgs["databases"]

    # Webapp servers
    Add-LogMessage -Level Info "Ensure webapp servers are bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.webapps.gitlab.vmName -VmResourceGroupName $config.sre.webapps.rg -NSGName $config.sre.webapps.nsg -NsgResourceGroupName $config.sre.network.vnet.rg -WarnOnFailure
    Add-VmToNSG -VMName $config.sre.webapps.hackmd.vmName -VmResourceGroupName $config.sre.webapps.rg -NSGName $config.sre.webapps.nsg -NsgResourceGroupName $config.sre.network.vnet.rg -WarnOnFailure
    $nsgs["webapps"] = Get-AzNetworkSecurityGroup -Name $config.sre.webapps.nsg -ResourceGroupName $config.sre.network.vnet.rg

    # Compute VMs
    Add-LogMessage -Level Info "Ensure compute VMs are bound to correct NSG..."
    $computeSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.compute.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
    $nsgs["compute"] = Get-AzNetworkSecurityGroup -Name $config.sre.network.vnet.subnets.compute.nsg.name -ResourceGroupName $config.sre.network.vnet.rg
    $computeSubnet = Set-SubnetNetworkSecurityGroup -Subnet $computeSubnet -NetworkSecurityGroup $nsgs["compute"]

    # Update NSG rules
    # ----------------
    # Update RDS Gateway NSG
    Add-LogMessage -Level Info "Setting inbound connection rules on RDS Gateway NSG..."
    $null = Update-NetworkSecurityGroupRule -Name "AllowHttpsInbound" -NetworkSecurityGroup $nsgs["gateway"] -SourceAddressPrefix $allowedSources

    # Update user-facing NSGs
    Add-LogMessage -Level Info "Setting outbound internet rules on user-facing NSGs..."
    $null = Update-NetworkSecurityGroupRule -Name $outboundInternetAccessRuleName -NetworkSecurityGroup $nsgs["compute"] -Access $config.sre.rds.gateway.networkRules.outboundInternet
    $null = Update-NetworkSecurityGroupRule -Name $outboundInternetAccessRuleName -NetworkSecurityGroup $nsgs["webapps"] -Access $config.sre.rds.gateway.networkRules.outboundInternet
}


# List all NICs associated with each NSG
# --------------------------------------
foreach ($nsgName in $nsgs.Keys) {
    Add-LogMessage -Level Info "NICs associated with $($nsgs[$nsgName].Name):"
    @($nsgs[$nsgName].NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }
    foreach ($linkedSubnet in $nsgs[$nsgName].Subnets) {
        $subnet = Get-Subnet -Name $linkedSubnet.Id.Split("/")[-1] -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
        $null = $subnet.IpConfigurations.Id | Where-Object { $_ } | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Split('/')[-3])" }
    }
}


# Ensure SRE is peered to correct mirror set
# ------------------------------------------
# Unpeer any existing networks before (re-)establishing correct peering for SRE
Invoke-Expression -Command "$(Join-Path $PSScriptRoot Unpeer_Sre_And_Mirror_Networks.ps1) -configId $configId"

if (@(2, 3).Contains([int]$config.sre.tier)) {
    Add-LogMessage -Level Info "Ensuring SRE is peered to correct mirror set..."

    # Peer this SRE to the repository network
    if ($config.sre.nexus -and ([int]$config.sre.tier -eq 2)) {
        if (-not $config.shm.network.repositoryVnet.name) {
            Add-LogMessage -Level Warning "No repository VNet is configured for SRE $($config.sre.id) [tier $($config.sre.tier)]. Nothing to do."
        } else {
            Set-VnetPeering -Vnet1Name $config.sre.network.vnet.name -Vnet1ResourceGroup $config.sre.network.vnet.rg -Vnet1SubscriptionName $config.sre.subscriptionName -Vnet2Name $config.shm.network.repositoryVnet.name -Vnet2ResourceGroup $config.shm.network.vnet.rg -Vnet2SubscriptionName $config.shm.subscriptionName
        }
    # Peer this SRE to the correct mirror network
    } else {
        if (-not $config.shm.network.mirrorVnets["tier$($config.sre.tier)"].name) {
            Add-LogMessage -Level Warning "No mirror VNet is configured for SRE $($config.sre.id) [tier $($config.sre.tier)]. Nothing to do."
        } else {
            Set-VnetPeering -Vnet1Name $config.sre.network.vnet.name -Vnet1ResourceGroup $config.sre.network.vnet.rg -Vnet1SubscriptionName $config.sre.subscriptionName -Vnet2Name $config.shm.network.mirrorVnets["tier$($config.sre.tier)"].name -Vnet2ResourceGroup $config.shm.network.vnet.rg -Vnet2SubscriptionName $config.shm.subscriptionName
        }
    }
}


# Update SRE mirror lookup
# ------------------------
Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
$IPs = Get-MirrorIPs $config
$addresses = Get-MirrorAddresses -cranIp $IPs.cran -pypiIp $IPs.pypi -nexus $config.sre.nexus
Add-LogMessage -Level Info "CRAN: '$($addresses.cran.url)'"
Add-LogMessage -Level Info "PyPI: '$($addresses.pypi.index)'"

# Set PyPI and CRAN locations on the compute VM
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "update_mirror_settings.sh"
foreach ($vmName in $computeVmNames) {
    Add-LogMessage -Level Info "Setting PyPI and CRAN locations on compute VM: $($vmName)"
    $params = @{
        CRAN_MIRROR_INDEX_URL = "`"$($addresses.cran.url)`""
        PYPI_MIRROR_INDEX     = "`"$($addresses.pypi.index)`""
        PYPI_MIRROR_INDEX_URL = "`"$($addresses.pypi.indexUrl)`""
        PYPI_MIRROR_HOST      = "`"$($addresses.pypi.host)`""
    }
    $null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Block external DNS queries
# --------------------------
Invoke-Expression -Command "$(Join-Path $PSScriptRoot Block_External_DNS_Queries.ps1) -configId $configId"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
