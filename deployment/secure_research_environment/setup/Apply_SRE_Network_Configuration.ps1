param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Mirrors.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Ensure VMs are bound to correct NSGs
# ------------------------------------
Add-LogMessage -Level Info "Applying network configuration for SRE '$($config.sre.id)' (Tier $($config.sre.tier)), hosted on subscription '$($config.sre.subscriptionName)'"
$nsgs = @{}

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


# List all NICs associated with each NSG
# --------------------------------------
foreach ($nsgName in $nsgs.Keys) {
    Add-LogMessage -Level Info "NICs associated with $($nsgs[$nsgName].Name):"
    @($nsgs[$nsgName].NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }
}


# Update NSG rules
# ----------------

# Update RDS Gateway NSG
Add-LogMessage -Level Info "Setting inbound connection rules on RDS Gateway NSG..."
$allowedSources = ($config.sre.rds.gateway.networkRules.allowedSources.Split(',') | ForEach-Object { $_.Trim() })  # NB. Use an array, splitting on commas and trimming any whitespace from each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$null = Update-NetworkSecurityGroupRule -Name "HttpsIn" -NetworkSecurityGroup $nsgs[$config.sre.rds.gateway.nsg] -SourceAddressPrefix $allowedSources

# Update user-facing NSGs
Add-LogMessage -Level Info "Setting outbound internet rules on user-facing NSGs..."
$null = Update-NetworkSecurityGroupRule -Name "OutboundInternetAccess" -NetworkSecurityGroup $nsgs[$config.sre.dsvm.nsg] -Access $config.sre.rds.gateway.networkRules.outboundInternet
$null = Update-NetworkSecurityGroupRule -Name "OutboundInternetAccess" -NetworkSecurityGroup $nsgs[$config.sre.webapps.nsg] -Access $config.sre.rds.gateway.networkRules.outboundInternet


# Ensure SRE is peered to correct mirror set
# ------------------------------------------
Add-LogMessage -Level Info "Ensuring SRE is peered to correct mirror set..."

# Unpeer any existing networks before (re-)establishing correct peering for SRE
Invoke-Expression -Command "$(Join-Path $PSScriptRoot Unpeer_Sre_And_Mirror_Networks.ps1) -configId $configId"

# Re-peer to the correct network for this SRE
Add-LogMessage -Level Info "Peering to the correct mirror network..."
if (-not $config.shm.network.mirrorVnets["tier$($config.sre.tier)"].name) {
    Add-LogMessage -Level Info "No mirror VNet is configured for Tier $($config.sre.tier) SRE $($config.sre.id). Nothing to do."
} else {
    New-VnetPeering -Vnet1Name $config.sre.network.vnet.name -Vnet1ResourceGroup $config.sre.network.vnet.rg -Vnet1SubscriptionName $config.sre.subscriptionName -Vnet2Name $config.shm.network.mirrorVnets["tier$($config.sre.tier)"].name -Vnet2ResourceGroup $config.shm.network.vnet.rg -Vnet2SubscriptionName $config.shm.subscriptionName
}

# Ensure SRE is peered to the Nexus repository
# --------------------------------------------
Add-LogMessage -Level Info "Peering to the repository network..."
if (-not $config.shm.network.repositoryVnet.name) {
    Add-LogMessage -Level Info "No repository VNet is configured for SRE $($config.sre.id). Nothing to do."
} else {
    New-VnetPeering -Vnet1Name $config.sre.network.vnet.name -Vnet1ResourceGroup $config.sre.network.vnet.rg -Vnet1SubscriptionName $config.sre.subscriptionName -Vnet2Name $config.shm.network.repositoryVnet.name -Vnet2ResourceGroup $config.shm.network.vnet.rg -Vnet2SubscriptionName $config.shm.subscriptionName
}


# Update SRE mirror lookup
# ------------------------
if ($config.sre.tier -in @(2,3)) {
    Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
    if ($config.sre.tier == 2) {
        $pypiIp = $config.shm.repository.nexus.ipAddress
        $cranIp = $config.shm.repository.nexus.ipAddress
        $useNexus = $True
    } else if ($config.sre.tier == 3) {
        $pypiIp = $config.shm.mirrors.pypi.tier3.internal.ipAddress
        $cranIp = $config.shm.mirrors.cran.tier3.internal.ipAddress
        $useNexus = $False
    }

    $addresses = Get-MirrorAddresses -cranIp $cranIp -pypiIp $pypiIp -nexus $useNexus
    $success = $?
    Add-LogMessage -Level Info "CRAN: '$($addresses.cran.url)'"
    Add-LogMessage -Level Info "PyPI: '$($addresses.pypi.index)'"
    if ($success) {
        Add-LogMessage -Level Success "Successfully loaded package mirror URLs"
    } else {
        Add-LogMessage -Level Fatal "Failed to load package mirror URLs!"
    }
}

# Set PyPI and CRAN locations on the compute VM
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "update_mirror_settings.sh"
foreach ($vmName in $computeVmNames) {
    Add-LogMessage -Level Info "Setting PyPI and CRAN locations on compute VM: $($vmName)"
    $params = @{
        CRAN_MIRROR_IP = "`"$($addresses.cran.url)`""
        PYPI_MIRROR_INDEX = "`"$($addresses.pypi.index)`""
        PYPI_MIRROR_INDEX_URL = "`"$($addresses.pypi.indexUrl)`""
        PYPI_MIRROR_HOST = "`"$($addresses.pypi.host)`""
    }
    $result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
    Write-Output $result.Value
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
