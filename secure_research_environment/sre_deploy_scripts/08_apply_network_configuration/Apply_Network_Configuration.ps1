param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Mirrors.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Set common variables
# --------------------
Add-LogMessage -Level Info "Applying network configuration for SRE '$($config.sre.id)' (Tier $($config.sre.tier)), hosted on subscription '$($config.sre.subscriptionName)'"
# Get NSGs
$nsgGateway = Get-AzNetworkSecurityGroup -Name $config.sre.rds.gateway.nsg
if ($nsgGateway -eq $null) { throw "Could not load RDS gateway NSG" }
$nsgLinux = Get-AzNetworkSecurityGroup -Name $config.sre.webapps.nsg
if ($nsgLinux -eq $null) { throw "Could not load Linux VMs NSG" }
$nsgSessionHosts = Get-AzNetworkSecurityGroup -Name $config.sre.rds.sessionHost1.nsg
if ($nsgSessionHosts -eq $null) { throw "Could not load RDS session hosts NSG" }


# Ensure RDS session hosts and dataserver are bound to session hosts NSG
# ----------------------------------------------------------------------
Add-LogMessage -Level Info "Ensure RDS session hosts and data server are bound to correct Network Security Group (NSG)..."
foreach ($vmName in ($config.sre.rds.sessionHost1.vmName, $config.sre.rds.sessionHost2.vmName, $config.sre.dataserver.vmName)) {
    Add-VmToNSG -VMName $vmName -NSGName $nsgSessionHosts.Name
}
Start-Sleep -Seconds 30
Add-LogMessage -Level Info "NICs associated with $($nsgSessionHosts.Name):"
@($nsgSessionHosts.NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }


# Ensure webapp servers and compute VMs are bound to webapp NSG
# -------------------------------------------------------------
Add-LogMessage -Level Info "Ensure webapp servers and compute VMs are bound to correct NSG..."
$computeVMs = Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | ForEach-Object { $_.Name }
$webappVMs = $config.sre.webapps.gitlab.vmName, $config.sre.webapps.hackmd.vmName
foreach ($vmName in ([array]$computeVMs + $webappVMs)) {
    Add-VmToNSG -VMName $vmName -NSGName $nsgLinux.Name
}
Start-Sleep -Seconds 30
Add-LogMessage -Level Info "NICs associated with $($nsgLinux.Name):"
@($nsgLinux.NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }


# Ensure VMs are bound to correct NSGs
# ------------------------------------
Add-LogMessage -Level Info "Ensure DC is bound to correct NSG..."
Add-VmToNSG -VMName $config.sre.dc.vmName -NSGName $config.sre.dc.nsg
Add-LogMessage -Level Info "Ensure RDS gateway is bound to correct NSG..."
Add-VmToNSG -VMName $config.sre.rds.gateway.vmName -NSGName $config.sre.rds.gateway.nsg
Add-LogMessage -Level Info "Ensure RDS session hosts are bound to correct NSG..."
Add-VmToNSG -VMName $config.sre.rds.sessionHost1.vmName -NSGName $config.sre.rds.sessionHost1.nsg
Add-VmToNSG -VMName $config.sre.rds.sessionHost2.vmName -NSGName $config.sre.rds.sessionHost2.nsg
Add-LogMessage -Level Info "Ensure data server is bound to correct NSG..."
Add-VmToNSG -VMName $config.sre.dataserver.vmName -NSGName $config.sre.dataserver.nsg
Add-LogMessage -Level Info "Ensure webapp servers are bound to correct NSG..."
Add-VmToNSG -VMName $config.sre.webapps.gitlab.vmName -NSGName $config.sre.webapps.nsg
Add-VmToNSG -VMName $config.sre.webapps.hackmd.vmName -NSGName $config.sre.webapps.nsg
Add-LogMessage -Level Info "Ensure compute VMs are bound to correct NSG..."
$computeVMs = Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | ForEach-Object { $_.Name }
foreach ($vmName in $computeVMs) {
    Add-VmToNSG -VMName $vmName -NSGName $config.sre.dsvm.nsg
}


# Update NSG rules
# ----------------

# Update RDS Gateway NSG
Add-LogMessage -Level Info "Updating RDS Gateway NSG to match SRE config..."
$allowedSources = ($config.sre.rds.gateway.networkRules.allowedSources.Split(',') | ForEach-Object { $_.Trim() })  # NB. Use an array, splitting on commas and trimming any whitespace from each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$_ = Update-NetworkSecurityGroupRule -Name "HttpsIn" -NetworkSecurityGroup $nsgGateway -SourceAddressPrefix $allowedSources

# Update restricted Linux NSG
Add-LogMessage -Level Info "Updating restricted Linux NSG to match SRE config..."
$_ = Update-NetworkSecurityGroupRule -Name "OutboundDenyInternet" -NetworkSecurityGroup $nsgLinux -Access $config.sre.rds.gateway.networkRules.outboundInternet


# Ensure SRE is peered to correct mirror set
# ------------------------------------------
Add-LogMessage -Level Info "Ensuring SRE is peered to correct mirror set..."

# Unpeer any existing networks before (re-)establishing correct peering for SRE
Invoke-Expression -Command "$(Join-Path $PSScriptRoot Unpeer_Sre_And_Mirror_Networks.ps1) -sreId $sreId"

# Re-peer to the correct network for this SRE
Add-LogMessage -Level Info "Peering to the correct mirror network..."
if (!$config.sre.mirrors.vnet.Name) {
    Write-Host -ForegroundColor DarkGreen "No mirror VNet is configured for Tier $($config.sre.tier) SRE $($config.sre.id). Nothing to do."
} else {
    # Fetch SRE and mirror VNets
    $sreVnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.Name -ResourceGroupName $config.sre.network.vnet.rg
    $_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
    $mirrorVnet = Get-AzVirtualNetwork -Name $config.sre.mirrors.vnet.Name -ResourceGroupName $config.shm.network.vnet.rg

    # Add peering to Mirror Vnet
    $peeringName = "PEER_$($config.sre.network.vnet.Name)"
    Add-LogMessage -Level Info "[ ] Adding peering '$peeringName' to mirror VNet '$mirrorVnet'."
    $_ = Add-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetwork $mirrorVnet -RemoteVirtualNetworkId $sreVnet.Id
    if ($?) {
        Add-LogMessage -Level Success "Adding peering '$peeringName' succeeded"
    } else {
        Add-LogMessage -Level Fatal "Adding peering '$peeringName' failed!"
    }

    # Add Peering to SRE Vnet
    $_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
    $peeringName = "PEER_$($config.sre.mirrors.vnet.Name)"
    Add-LogMessage -Level Info "[ ] Adding peering '$peeringName' to SRE VNet '$sreVnet'."
    $_ = Add-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetwork $sreVnet -RemoteVirtualNetworkId $mirrorVnet.Id
    if ($?) {
        Add-LogMessage -Level Success "Adding peering '$peeringName' succeeded"
    } else {
        Add-LogMessage -Level Fatal "Adding peering '$peeringName' failed!"
    }
}


# Update SRE mirror lookup
# ------------------------
Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
$addresses = Get-MirrorAddresses -cranIp $config.sre.mirrors.cran.ip -pypiIp $config.sre.mirrors.pypi.ip
Add-LogMessage -Level Info "CRAN: '$($addresses.cran.url)'"
Add-LogMessage -Level Info "PyPI server: '$($addresses.pypi.url)'"
Add-LogMessage -Level Info "PyPI host: '$($addresses.pypi.host)'"

# Set PyPI and CRAN locations on the compute VM
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "update_mirror_settings.sh"
foreach ($vmName in $computeVMs) {
    Add-LogMessage -Level Info "Setting PyPI and CRAN locations on compute VM: $($vmName)"
    $params = @{
        CRAN_MIRROR_IP = "`"$($addresses.cran.url)`""
        PYPI_MIRROR_IP = "`"$($addresses.pypi.url)`""
        PYPI_MIRROR_HOST = "`"$($addresses.pypi.host)`""
    }
    $result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
    Write-Output $result.Value
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
