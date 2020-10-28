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
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Get common parameters
# ---------------------
$allowedSources = ($config.sre.rds.gateway.networkRules.allowedSources.Split(',') | ForEach-Object { $_.Trim() })  # NB. Use an array, splitting on commas and trimming any whitespace from each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$nsgs = @{}


# Ensure VMs are bound to correct NSGs
# ------------------------------------
Add-LogMessage -Level Info "Applying network configuration for SRE '$($config.sre.id)' (Tier $($config.sre.tier)), hosted on subscription '$($config.sre.subscriptionName)'"


# Tier-1 and below have single NSG
# --------------------------------
if (@(0, 1).Contains([int]$config.sre.tier)) {
    $nsgs[$config.sre.dsvm.nsg] = Get-AzNetworkSecurityGroup -Name $config.sre.dsvm.nsg -ResourceGroupName $config.sre.network.vnet.rg

    Add-LogMessage -Level Info "Setting inbound connection rules on user-facing NSG..."
    $null = Update-NetworkSecurityGroupRule -Name "InboundSSHAccess" -NetworkSecurityGroup $nsgs[$config.sre.dsvm.nsg] -SourceAddressPrefix $allowedSources

    Add-LogMessage -Level Info "Setting outbound connection rules on user-facing NSG..."
    $null = Update-NetworkSecurityGroupRule -Name "OutboundInternetAccess" -NetworkSecurityGroup $nsgs[$config.sre.dsvm.nsg] -Access $config.sre.rds.gateway.networkRules.outboundInternet


# Tier-2 and above have several NSGs
# ----------------------------------
} else {
    # RDS gateway
    Add-LogMessage -Level Info "Ensure RDS gateway is bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.rds.gateway.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.gateway.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
    $nsgs[$config.sre.rds.gateway.nsg] = Get-AzNetworkSecurityGroup -Name $config.sre.rds.gateway.nsg -ResourceGroupName $config.sre.network.vnet.rg

    # RDS sesssion hosts
    Add-LogMessage -Level Info "Ensure RDS session hosts are bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.rds.appSessionHost.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.appSessionHost.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
    $nsgs[$config.sre.rds.appSessionHost.nsg] = Get-AzNetworkSecurityGroup -Name $config.sre.rds.appSessionHost.nsg -ResourceGroupName $config.sre.network.vnet.rg

    # Data server
    Add-LogMessage -Level Info "Ensure data server is bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.dataserver.vmName -VmResourceGroupName $config.sre.dataserver.rg -NSGName $config.sre.dataserver.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
    $nsgs[$config.sre.dataserver.nsg] = Get-AzNetworkSecurityGroup -Name $config.sre.dataserver.nsg -ResourceGroupName $config.sre.network.vnet.rg

    # Webapp servers
    Add-LogMessage -Level Info "Ensure webapp servers are bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.webapps.gitlab.vmName -VmResourceGroupName $config.sre.webapps.rg -NSGName $config.sre.webapps.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
    Add-VmToNSG -VMName $config.sre.webapps.hackmd.vmName -VmResourceGroupName $config.sre.webapps.rg -NSGName $config.sre.webapps.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
    $nsgs[$config.sre.webapps.nsg] = Get-AzNetworkSecurityGroup -Name $config.sre.webapps.nsg -ResourceGroupName $config.sre.network.vnet.rg

    # Compute VMs
    Add-LogMessage -Level Info "Ensure compute VMs are bound to correct NSG..."
    $computeVmNames = $(Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | ForEach-Object { $_.Name })
    foreach ($vmName in $computeVmNames) {
        Add-VmToNSG -VMName $vmName -VmResourceGroupName $config.sre.dsvm.rg -NSGName $config.sre.dsvm.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
    }
    $nsgs[$config.sre.dsvm.nsg] = Get-AzNetworkSecurityGroup -Name $config.sre.dsvm.nsg -ResourceGroupName $config.sre.network.vnet.rg

    # Update NSG rules
    # ----------------

    # Update RDS Gateway NSG
    Add-LogMessage -Level Info "Setting inbound connection rules on RDS Gateway NSG..."
    $null = Update-NetworkSecurityGroupRule -Name "HttpsIn" -NetworkSecurityGroup $nsgs[$config.sre.rds.gateway.nsg] -SourceAddressPrefix $allowedSources

    # Update user-facing NSGs
    Add-LogMessage -Level Info "Setting outbound internet rules on user-facing NSGs..."
    $null = Update-NetworkSecurityGroupRule -Name "OutboundInternetAccess" -NetworkSecurityGroup $nsgs[$config.sre.dsvm.nsg] -Access $config.sre.rds.gateway.networkRules.outboundInternet
    $null = Update-NetworkSecurityGroupRule -Name "OutboundInternetAccess" -NetworkSecurityGroup $nsgs[$config.sre.webapps.nsg] -Access $config.sre.rds.gateway.networkRules.outboundInternet
}


# List all NICs associated with each NSG
# --------------------------------------
foreach ($nsgName in $nsgs.Keys) {
    Add-LogMessage -Level Info "NICs associated with $($nsgs[$nsgName].Name):"
    @($nsgs[$nsgName].NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }
}


# Ensure SRE is peered to correct mirror set
# ------------------------------------------
if (@(2, 3).Contains([int]$config.sre.tier)) {
    Add-LogMessage -Level Info "Ensuring SRE is peered to correct mirror set..."

    # Unpeer any existing networks before (re-)establishing correct peering for SRE
    Invoke-Expression -Command "$(Join-Path $PSScriptRoot Unpeer_Sre_And_Mirror_Networks.ps1) -configId $configId"

    # Re-peer to the correct network for this SRE
    Add-LogMessage -Level Info "Peering to the correct mirror network..."
    if (-not $config.shm.network.mirrorVnets["tier$($config.sre.tier)"].name) {
        Add-LogMessage -Level Info "No mirror VNet is configured for Tier $($config.sre.tier) SRE $($config.sre.id). Nothing to do."
    } else {
        # Fetch SRE and mirror VNets
        try {
            $sreVnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
            $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
            $mirrorVnet = Get-AzVirtualNetwork -Name $config.shm.network.mirrorVnets["tier$($config.sre.tier)"].name -ResourceGroupName $config.shm.network.vnet.rg -ErrorAction Stop

            # Add peering to Mirror Vnet
            $peeringName = "PEER_$($sreVnet.Name)"
            Add-LogMessage -Level Info "[ ] Adding peering '$peeringName' to mirror VNet $($mirrorVnet.Name)."
            $null = Add-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetwork $mirrorVnet -RemoteVirtualNetworkId $sreVnet.Id
            if ($?) {
                Add-LogMessage -Level Success "Adding peering '$peeringName' succeeded"
            } else {
                Add-LogMessage -Level Fatal "Adding peering '$peeringName' failed!"
            }

            # Add Peering to SRE Vnet
            $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
            $peeringName = "PEER_$($mirrorVnet.Name)"
            Add-LogMessage -Level Info "[ ] Adding peering '$peeringName' to SRE VNet $($sreVnet.Name)."
            $null = Add-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetwork $sreVnet -RemoteVirtualNetworkId $mirrorVnet.Id
            if ($?) {
                Add-LogMessage -Level Success "Adding peering '$peeringName' succeeded"
            } else {
                Add-LogMessage -Level Fatal "Adding peering '$peeringName' failed!"
            }
        } catch [Microsoft.Azure.Commands.Network.Common.NetworkCloudException] {
            Add-LogMessage -Level Warning "Mirror VNet could not be loaded! Did you deploy tier-$($config.sre.tier) mirrors?"
        }
    }
}


# Update SRE mirror lookup
# ------------------------
Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
$addresses = Get-MirrorAddresses -cranIp $config.shm.mirrors.cran["tier$($config.sre.tier)"].internal.ipAddress -pypiIp $config.shm.mirrors.pypi["tier$($config.sre.tier)"].internal.ipAddress
Add-LogMessage -Level Info "CRAN: '$($addresses.cran.url)'"
Add-LogMessage -Level Info "PyPI server: '$($addresses.pypi.url)'"
Add-LogMessage -Level Info "PyPI host: '$($addresses.pypi.host)'"

# Set PyPI and CRAN locations on the compute VM
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "update_mirror_settings.sh"
foreach ($vmName in $computeVmNames) {
    Add-LogMessage -Level Info "Setting PyPI and CRAN locations on compute VM: $($vmName)"
    $params = @{
        CRAN_MIRROR_IP   = "`"$($addresses.cran.url)`""
        PYPI_MIRROR_IP   = "`"$($addresses.pypi.url)`""
        PYPI_MIRROR_HOST = "`"$($addresses.pypi.host)`""
    }
    $result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
    Write-Output $result.Value
}


# Block external DNS qeuries
# --------------------------
Invoke-Expression -Command "$(Join-Path $PSScriptRoot Block_External_DNS_Queries.ps1) -configId $configId"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
