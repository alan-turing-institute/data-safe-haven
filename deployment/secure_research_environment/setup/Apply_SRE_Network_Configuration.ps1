param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Get common parameters
# ---------------------
$allowedSources = ($config.sre.remoteDesktop.networkRules.allowedSources.Split(',') | ForEach-Object { $_.Trim() })  # NB. Use an array, splitting on commas and trimming any whitespace from each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$outboundInternetAccessRuleName = "$($config.sre.remoteDesktop.networkRules.outboundInternet)InternetOutbound"
$nsgs = @{}


# Ensure VMs are bound to correct NSGs
# ------------------------------------
Add-LogMessage -Level Info "Applying network configuration for SRE '$($config.sre.id)' (Tier $($config.sre.tier)), hosted on subscription '$($config.sre.subscriptionName)'"


# ApacheGuacamole and MicrosoftRDS have several NSGs
# --------------------------------------------------
# Remote desktop
if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
    # RDS gateway
    Add-LogMessage -Level Info "Ensure Guacamole server is bound to correct NSG..."
    $remoteDesktopSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.remoteDesktop.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
    $nsgs["remoteDesktop"] = Get-AzNetworkSecurityGroup -Name $config.sre.network.vnet.subnets.remoteDesktop.nsg.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
    $remoteDesktopSubnet = Set-SubnetNetworkSecurityGroup -Subnet $remoteDesktopSubnet -NetworkSecurityGroup $nsgs["remoteDesktop"] -ErrorAction Stop
} elseif ($config.sre.remoteDesktop.provider -eq "MicrosoftRDS") {
    # RDS gateway
    Add-LogMessage -Level Info "Ensure RDS gateway is bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.remoteDesktop.gateway.vmName -VmResourceGroupName $config.sre.remoteDesktop.rg -NSGName $config.sre.remoteDesktop.gateway.nsg.name -NsgResourceGroupName $config.sre.network.vnet.rg
    $nsgs["gateway"] = Get-AzNetworkSecurityGroup -Name $config.sre.remoteDesktop.gateway.nsg.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
    # RDS sesssion hosts
    Add-LogMessage -Level Info "Ensure RDS session hosts are bound to correct NSG..."
    Add-VmToNSG -VMName $config.sre.remoteDesktop.appSessionHost.vmName -VmResourceGroupName $config.sre.remoteDesktop.rg -NSGName $config.sre.remoteDesktop.appSessionHost.nsg.name -NsgResourceGroupName $config.sre.network.vnet.rg
    $nsgs["sessionhosts"] = Get-AzNetworkSecurityGroup -Name $config.sre.remoteDesktop.appSessionHost.nsg.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
} else {
    Add-LogMessage -Level Fatal "Remote desktop type '$($config.sre.remoteDesktop.type)' was not recognised!"
}

# Database servers
Add-LogMessage -Level Info "Ensure database servers are bound to correct NSG..."
$databaseSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.databases.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
$nsgs["databases"] = Get-AzNetworkSecurityGroup -Name $config.sre.network.vnet.subnets.databases.nsg.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$databaseSubnet = Set-SubnetNetworkSecurityGroup -Subnet $databaseSubnet -NetworkSecurityGroup $nsgs["databases"] -ErrorAction Stop

# Webapp servers
Add-LogMessage -Level Info "Ensure webapp servers are bound to correct NSG..."
$webappsSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.webapps.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
$nsgs["webapps"] = Get-AzNetworkSecurityGroup -Name $config.sre.network.vnet.subnets.webapps.nsg.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$webappsSubnet = Set-SubnetNetworkSecurityGroup -Subnet $webappsSubnet -NetworkSecurityGroup $nsgs["webapps"] -ErrorAction Stop

# Compute VMs
Add-LogMessage -Level Info "Ensure compute VMs are bound to correct NSG..."
$computeSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.compute.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
$nsgs["compute"] = Get-AzNetworkSecurityGroup -Name $config.sre.network.vnet.subnets.compute.nsg.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$computeSubnet = Set-SubnetNetworkSecurityGroup -Subnet $computeSubnet -NetworkSecurityGroup $nsgs["compute"] -ErrorAction Stop

# Update remote desktop server NSG rules
if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
    Add-LogMessage -Level Info "Setting inbound connection rules on Guacamole NSG..."
    $null = Update-NetworkSecurityGroupRule -Name "AllowHttpsInbound" -NetworkSecurityGroup $nsgs["remoteDesktop"] -SourceAddressPrefix $allowedSources
} elseif ($config.sre.remoteDesktop.provider -eq "MicrosoftRDS") {
    Add-LogMessage -Level Info "Setting inbound connection rules on RDS Gateway NSG..."
    $null = Update-NetworkSecurityGroupRule -Name "AllowHttpsInbound" -NetworkSecurityGroup $nsgs["gateway"] -SourceAddressPrefix $allowedSources
} else {
    Add-LogMessage -Level Fatal "Remote desktop type '$($config.sre.remoteDesktop.type)' was not recognised!"
}

# Update user-facing NSG rules
Add-LogMessage -Level Info "Setting outbound internet rules on user-facing NSGs..."
$null = Update-NetworkSecurityGroupRule -Name $outboundInternetAccessRuleName -NetworkSecurityGroup $nsgs["compute"] -Access $config.sre.remoteDesktop.networkRules.outboundInternet
$null = Update-NetworkSecurityGroupRule -Name $outboundInternetAccessRuleName -NetworkSecurityGroup $nsgs["webapps"] -Access $config.sre.remoteDesktop.networkRules.outboundInternet
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
Invoke-Expression -Command "$(Join-Path $PSScriptRoot Unpeer_Sre_And_Mirror_Networks.ps1) -shmId $shmId -sreId $sreId"
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


# Update SRE package repository details
# -------------------------------------
# Set PyPI and CRAN locations on the compute VM
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "update_mirror_settings.sh"
$repositoryFacingVms = Get-AzVM | Where-Object { ($_.ResourceGroupName -eq $config.sre.dsvm.rg) -or ($_.Name -eq $config.sre.webapps.cocalc.vmName) }
foreach ($VM in $repositoryFacingVms) {
    Add-LogMessage -Level Info "Ensuring that PyPI and CRAN locations are set correctly on $($VM.Name)"
    $params = @{
        CRAN_MIRROR_INDEX_URL = $config.sre.repositories.cran.url
        PYPI_MIRROR_INDEX     = $config.sre.repositories.pypi.index
        PYPI_MIRROR_INDEX_URL = $config.sre.repositories.pypi.indexUrl
        PYPI_MIRROR_HOST      = $config.sre.repositories.pypi.host
    }
    $null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $VM.Name -ResourceGroupName $VM.ResourceGroupName -Parameter $params
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Block external DNS queries
# --------------------------
Invoke-Expression -Command "$(Join-Path $PSScriptRoot Configure_External_DNS_Queries.ps1) -shmId $shmId -sreId $sreId"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
