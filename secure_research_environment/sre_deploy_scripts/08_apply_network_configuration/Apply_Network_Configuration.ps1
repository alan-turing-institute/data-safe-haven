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
$nsgGateway = Get-AzNetworkSecurityGroup -Name $config.sre.rds.nsg.gateway.name
if ($nsgGateway -eq $null) { throw "Could not load RDS gateway NSG" }
$nsgLinux = Get-AzNetworkSecurityGroup -Name $config.sre.webapps.nsg
if ($nsgLinux -eq $null) { throw "Could not load Linux VMs NSG" }
$nsgSessionHosts = Get-AzNetworkSecurityGroup -Name $config.sre.rds.nsg.session_hosts.name
if ($nsgSessionHosts -eq $null) { throw "Could not load RDS session hosts NSG" }
# Load allowed sources into an array, splitting on commas and trimming any whitespace from each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$allowedSources = ($config.sre.rds.nsg.gateway.allowedSources.Split(',') | ForEach-Object { $_.Trim() })


# Ensure RDS session hosts and dataserver are bound to session hosts NSG
# ----------------------------------------------------------------------
Add-LogMessage -Level Info "Ensure RDS session hosts and data server are bound to correct Network Security Group (NSG)..."
foreach ($vmName in ($config.sre.rds.sessionHost1.vmName, $config.sre.rds.sessionHost2.vmName, $config.sre.dataserver.vmName)) {
    Add-VmToNSG -VMName $vmName -NSGName $nsgSessionHosts.Name
}
Start-Sleep -Seconds 30
Add-LogMessage -Level Info "Summary: NICs associated with '$($nsgSessionHosts.Name)' NSG"
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
Add-LogMessage -Level Info "Summary: NICs associated with '$($nsgLinux.Name)' NSG"
@($nsgLinux.NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }


# Update RDS Gateway NSG to match SRE config
# ------------------------------------------
Add-LogMessage -Level Info "Updating RDS Gateway NSG to match SRE config"
# Update RDS Gateway NSG inbound access rule
$ruleName = "HTTPS_In"
$ruleBefore = Get-AzNetworkSecurityRuleConfig -Name $ruleName -NetworkSecurityGroup $nsgGateway
Add-LogMessage -Level Info "[ ] Updating '$($ruleName)' rule on '$($nsgGateway.name)' NSG to '$($ruleBefore.Access)' access from '$allowedSources' (was previously '$($ruleBefore.SourceAddressPrefix)')"
$params = @{
    Name = $ruleName
    NetworkSecurityGroup = $nsgGateway
    Description = "Allow HTTPS inbound to RDS server"
    Access = "Allow"
    Direction = "Inbound"
    SourceAddressPrefix = $allowedSources
    Protocol = "TCP"
    SourcePortRange = "*"
    DestinationPortRange = "443"
    DestinationAddressPrefix = "*"
    Priority = "101"
}
# Update rule and NSG (both are required)
$_ = Set-AzNetworkSecurityRuleConfig @params
$_ = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgGateway
# Confirm update has being successfully applied
$ruleAfter = Get-AzNetworkSecurityRuleConfig -Name $ruleName -NetworkSecurityGroup $nsgGateway
if ("$($ruleAfter.SourceAddressPrefix)" -eq "$allowedSources") {
    Add-LogMessage -Level Success "'$ruleName' on '$($nsgGateway.name)' NSG will now '$($ruleAfter.Access)' access from '$($ruleAfter.SourceAddressPrefix)'"
} else {
    Add-LogMessage -Level Fatal "'$ruleName' on '$($nsgGateway.name)' NSG will now '$($ruleAfter.Access)' access from '$($ruleAfter.SourceAddressPrefix)'"
}


# Update restricted Linux NSG to match SRE config
# -----------------------------------------------
Add-LogMessage -Level Info "Updating restricted Linux NSG to match SRE config..."
# Update RDS Gateway NSG inbound access rule
$ruleName = "Internet_Out"
$ruleBefore = Get-AzNetworkSecurityRuleConfig -Name $ruleName -NetworkSecurityGroup $nsgLinux
# Outbound access to Internet is Allowed for Tier 0 and 1 but Denied for Tier 2 and above
$access = $config.sre.rds.nsg.gateway.outboundInternet
Add-LogMessage -Level Info "[ ] Updating '$($ruleName)' rule on '$($nsgLinux.name)' NSG to '$access' access to '$($ruleBefore.DestinationAddressPrefix)' (was previously '$($ruleBefore.Access)')"
$params = @{
    Name = $ruleName
    NetworkSecurityGroup = $nsgLinux
    Description = "Control outbound internet access from user accessible VMs"
    Access = $access
    Direction = "Outbound"
    SourceAddressPrefix = "VirtualNetwork"
    Protocol = "*"
    SourcePortRange = "*"
    DestinationPortRange = "*"
    DestinationAddressPrefix = "Internet"
    Priority = "4000"
}
# Update rule and NSG (both are required)
$_ = Set-AzNetworkSecurityRuleConfig @params
$_ = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgLinux
# Confirm update has being successfully applied
$ruleAfter = Get-AzNetworkSecurityRuleConfig -Name $ruleName -NetworkSecurityGroup $nsgLinux
if ("$($ruleAfter.Access)" -eq "$access") {
    Add-LogMessage -Level Success "'$ruleName' on '$($nsgLinux.name)' NSG will now '$($ruleAfter.Access)' access to '$($ruleAfter.DestinationAddressPrefix)'"
} else {
    Add-LogMessage -Level Fatal "'$ruleName' on '$($nsgLinux.name)' NSG will now '$($ruleAfter.Access)' access to '$($ruleAfter.DestinationAddressPrefix)'"
}


# Ensure SRE is peered to correct mirror set
# ------------------------------------------
Add-LogMessage -Level Info "Ensuring SRE is peered to correct mirror set..."


# Unpeer any existing networks before (re-)establishing correct peering for SRE
# -----------------------------------------------------------------------------
Invoke-Expression -Command "$(Join-Path $PSScriptRoot Unpeer_Sre_And_Mirror_Networks.ps1) -sreId $sreId"

# Add-LogMessage -Level Info "Removing all existing mirror peerings..."
# $sreVnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.Name -ResourceGroupName $config.sre.network.vnet.rg

# # Get all mirror VNets from management subscription
# $_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
# $mirrorVnets = Get-AzVirtualNetwork | Where-Object { $_.Name -like "*PKG_MIRRORS*" }

# # Remove SHM side of mirror peerings involving this SRE
# foreach ($mirrorVnet in $mirrorVnets) {
#     $mirrorPeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $mirrorVnet.Name -ResourceGroupName $mirrorVnet.ResourceGroupName
#     foreach ($mirrorPeering in $mirrorPeerings) {
#         # Remove peerings that involve this SRE
#         if ($mirrorPeering.RemoteVirtualNetwork.Id -eq $sreVnet.Id) {
#             Add-LogMessage -Level Info "[ ] Removing peering $($mirrorPeering.Name): $($mirrorPeering.VirtualNetworkName) <-> $($sreVnet.Name)"
#             $_ = Remove-AzVirtualNetworkPeering -Name $mirrorPeering.Name -VirtualNetworkName $mirrorVnet.Name -ResourceGroupName $mirrorVnet.ResourceGroupName -Force
#             if ($?) {
#                 Add-LogMessage -Level Success "Peering removal succeeded"
#             } else {
#                 Add-LogMessage -Level Fatal "Peering removal failed!"
#             }
#         }
#     }
# }

# # Remove peering to this SRE from each SHM mirror network
# $_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
# $srePeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $sreVnet.Name -ResourceGroupName $sreVnet.ResourceGroupName
# foreach ($srePeering in $srePeerings) {
#     # Remove peerings that involve any of the mirror VNets
#     $peeredVnets = $mirrorVnets | Where-Object { $_.Id -eq $srePeering.RemoteVirtualNetwork.Id }
#     foreach ($mirrorVnet in $peeredVnets) {
#         Add-LogMessage -Level Info "[ ] Removing peering $($srePeering.Name): $($srePeering.VirtualNetworkName) <-> $($mirrorVnet.Name)"
#         $_ = Remove-AzVirtualNetworkPeering -Name $srePeering.Name -VirtualNetworkName $sreVnet.Name -ResourceGroupName $sreVnet.ResourceGroupName -Force
#         if ($?) {
#             Add-LogMessage -Level Success "Peering removal succeeded"
#         } else {
#             Add-LogMessage -Level Fatal "Peering removal failed!"
#         }
#     }
# }


# Re-peer to the correct network for this SRE
# -------------------------------------------
Add-LogMessage -Level Info "Peering to the correct mirror network..."
if (!$config.sre.mirrors.vnet.Name) {
    Write-Host -ForegroundColor DarkGreen "No mirror VNet is configured for Tier $($config.sre.tier) SRE $($config.sre.id). Nothing to do."
} else {
    # Fetch SRE and mirror VNets
    $sreVnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.Name -ResourceGroupName $config.sre.network.vnet.rg
    $_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
    $mirrorVnet = Get-AzVirtualNetwork -Name $config.sre.mirrors.vnet.Name -ResourceGroupName $config.shm.network.vnet.rg

    # Add peering to Mirror Vnet
    # $params = @{
    #     Name = "PEER_" + $config.sre.network.vnet.Name
    #     VirtualNetwork = $mirrorVnet
    #     RemoteVirtualNetworkId = $sreVnet.Id
    #     BlockVirtualNetworkAccess = $FALSE
    #     AllowForwardedTraffic = $FALSE
    #     AllowGatewayTransit = $FALSE
    #     UseRemoteGateways = $FALSE
    # }
    Add-LogMessage -Level Info "[ ] Adding peering '$($params.Name)' to mirror VNet '$($params.VirtualNetwork.Name)'."
    # $_ = Add-AzVirtualNetworkPeering @params
    $_ = Add-AzVirtualNetworkPeering -Name "PEER_$($config.sre.network.vnet.Name)" -VirtualNetwork $mirrorVnet -RemoteVirtualNetworkId $sreVnet.Id
    if ($?) {
        Add-LogMessage -Level Success "Peering addition succeeded"
    } else {
        Add-LogMessage -Level Fatal "Peering addition failed!"
    }

    # Add Peering to SRE Vnet
    $_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
    # $params = @{
    #     "Name" = "PEER_" + $config.sre.mirrors.vnet.Name
    #     "VirtualNetwork" = $sreVnet
    #     "RemoteVirtualNetworkId" = $mirrorVnet.Id
    #     "BlockVirtualNetworkAccess" = $FALSE
    #     "AllowForwardedTraffic" = $FALSE
    #     "AllowGatewayTransit" = $FALSE
    #     "UseRemoteGateways" = $FALSE
    # }
    Add-LogMessage -Level Info "[ ] Adding peering '$($params.Name)' to SRE VNet '$($params.VirtualNetwork.Name)'."
    # $_ = Add-AzVirtualNetworkPeering @params
    $_ = Add-AzVirtualNetworkPeering -Name "PEER_$($config.sre.mirrors.vnet.Name)" -VirtualNetwork $sreVnet -RemoteVirtualNetworkId $mirrorVnet.Id
    if ($?) {
        Add-LogMessage -Level Success "Peering addition succeeded"
    } else {
        Add-LogMessage -Level Fatal "Peering addition failed!"
    }
}


# Update SRE mirror lookup
# ------------------------
Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
$addresses = Get-MirrorAddresses -cranIp $config.sre.mirrors.cran.ip -pypiIp $config.sre.mirrors.pypi.ip
Add-LogMessage -Level Success "CRAN: '$($addresses.cran.url)'"
Add-LogMessage -Level Success "PyPI server: '$($addresses.pypi.url)'"
Add-LogMessage -Level Success "PyPI host: '$($addresses.pypi.host)'"

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
    # $result = Invoke-AzVMRunCommand -ResourceGroupName $config.sre.dsvm.rg -Name $vmName `
    #      -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
    # $success = $?
    # Write-Output $result.Value
    # if ($success) {
    #     Add-LogMessage -Level Success "Setting PyPI and CRAN locations on compute VM was successful"
    # } else {
    #     Add-LogMessage -Level Fatal "Setting PyPI and CRAN locations on compute VM failed!"
    # }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
