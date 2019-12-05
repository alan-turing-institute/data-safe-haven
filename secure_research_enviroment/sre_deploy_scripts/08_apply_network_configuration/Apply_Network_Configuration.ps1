param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force


# Get SRE config
# --------------
$config = Get-SreConfig($sreId);
$originalContext = Get-AzContext


# Set common variables
# --------------------
Write-Host -ForegroundColor DarkCyan "Applying network configuration for SRE '$($config.dsg.id)' (Tier $($config.dsg.tier)), hosted on subscription '$($config.dsg.subscriptionName)'"
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
# Get NSGs
$nsgGateway = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg | Where-Object { $_.Name -Like "NSG*SERVER*" }
if ($nsgGateway -eq $null) { throw "Could not load RDS gateway NSG" }
$nsgLinux = Get-AzNetworkSecurityGroup -Name $config.dsg.linux.nsg
if ($nsgLinux -eq $null) { throw "Could not load Linux VMs NSG" }
$nsgSessionHosts = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg | Where-Object { $_.Name -Like "NSG*SESSION*" }
if ($nsgSessionHosts -eq $null) { throw "Could not load RDS session hosts NSG" }
# Load allowed sources into an array, splitting on commas and trimming any whitespace from each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$allowedSources = ($config.dsg.rds.nsg.gateway.allowedSources.Split(',') | ForEach-Object{ $_.Trim() })


# Ensure RDS session hosts and dataserver are bound to session hosts NSG
# ----------------------------------------------------------------------
Write-Host -ForegroundColor DarkCyan "Ensure RDS session hosts and dataserver are bound to correct Network Security Group (NSG)..."
foreach ($vmName in ($config.dsg.rds.sessionHost1.vmName, $config.dsg.rds.sessionHost2.vmName, $config.dsg.dataserver.vmName)) {
    $nic = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $vmName).Id }
    Write-Host -ForegroundColor DarkCyan (" [ ] Associating $vmName with $($nsgSessionHosts.Name)...")
    $nic.NetworkSecurityGroup = $nsgSessionHosts;
    $_ = ($nic | Set-AzNetworkInterface);
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] NSG association succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] NSG association failed!"
    }
}
Start-Sleep -Seconds 30
Write-Host -ForegroundColor DarkCyan "Summary: NICs associated with '$($nsgSessionHosts.Name)' NSG"
@($nsgSessionHosts.NetworkInterfaces) | ForEach-Object{ Write-Host -ForegroundColor DarkGreen " [o] $($_.Id.Split('/')[-1])" }


# Ensure webapp servers and compute VMs are bound to webapp NSG
# -------------------------------------------------------------
Write-Host -ForegroundColor DarkCyan "Ensure webapp servers are bound to correct NSG..."
$computeVMs = Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg | % {$_.Name }
$webappVMs = $config.dsg.linux.gitlab.vmName, $config.dsg.linux.hackmd.vmName
foreach ($vmName in ([array]$computeVMs + $webappVMs)) {
    $nic = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $vmName).Id }
    Write-Host -ForegroundColor DarkCyan (" [ ] Associating $vmName with $($nsgLinux.Name)...")
    $nic.NetworkSecurityGroup = $nsgLinux;
    $_ = ($nic | Set-AzNetworkInterface);
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] NSG association succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] NSG association failed!"
    }
}
Start-Sleep -Seconds 30
Write-Host -ForegroundColor DarkCyan "Summary: NICs associated with '$($nsgLinux.Name)' NSG"
@($nsgLinux.NetworkInterfaces) | ForEach-Object{ Write-Host -ForegroundColor DarkGreen " [o] $($_.Id.Split('/')[-1])" }


# Update RDS Gateway NSG to match SRE config
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Updating RDS Gateway NSG to match SRE config"
# Update RDS Gateway NSG inbound access rule
$ruleName = "HTTPS_In"
$ruleBefore = Get-AzNetworkSecurityRuleConfig -Name $ruleName -NetworkSecurityGroup $nsgGateway;
Write-Host -ForegroundColor DarkCyan " [ ] Updating '$($ruleName)' rule on '$($nsgGateway.name)' NSG to '$($ruleBefore.Access)' access from '$allowedSources' (was previously '$($ruleBefore.SourceAddressPrefix)')"
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
$_ = Set-AzNetworkSecurityRuleConfig @params;
$_ = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgGateway;
# Confirm update has being successfully applied
$ruleAfter = Get-AzNetworkSecurityRuleConfig -Name $ruleName -NetworkSecurityGroup $nsgGateway;
if ("$($ruleAfter.SourceAddressPrefix)" -eq "$allowedSources") {
    Write-Host -ForegroundColor DarkGreen " [o] '$ruleName' on '$($nsgGateway.name)' NSG will now '$($ruleAfter.Access)' access from '$($ruleAfter.SourceAddressPrefix)'"
} else {
    Write-Host -ForegroundColor DarkRed " [x] '$ruleName' on '$($nsgGateway.name)' NSG will now '$($ruleAfter.Access)' access from '$($ruleAfter.SourceAddressPrefix)'"
}

# Update restricted Linux NSG to match SRE config
# -----------------------------------------------
Write-Host -ForegroundColor DarkCyan "Updating restricted Linux NSG to match SRE config..."
# Update RDS Gateway NSG inbound access rule
$ruleName = "Internet_Out"
$ruleBefore = Get-AzNetworkSecurityRuleConfig -Name $ruleName -NetworkSecurityGroup $nsgLinux;
# Outbound access to Internet is Allowed for Tier 0 and 1 but Denied for Tier 2 and above
$access = $config.dsg.rds.nsg.gateway.outboundInternet
Write-Host -ForegroundColor DarkCyan " [ ] Updating '$($ruleName)' rule on '$($nsgLinux.name)' NSG to '$access' access to '$($ruleBefore.DestinationAddressPrefix)' (was previously '$($ruleBefore.Access)')"
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
$_ = Set-AzNetworkSecurityRuleConfig @params;
$_ = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgLinux;
# Confirm update has being successfully applied
$ruleAfter = Get-AzNetworkSecurityRuleConfig -Name $ruleName -NetworkSecurityGroup $nsgLinux;
if ("$($ruleAfter.Access)" -eq "$access") {
    Write-Host -ForegroundColor DarkGreen " [o] '$ruleName' on '$($nsgLinux.name)' NSG will now '$($ruleAfter.Access)' access to '$($ruleAfter.DestinationAddressPrefix)'"
} else {
    Write-Host -ForegroundColor DarkRed " [x] '$ruleName' on '$($nsgLinux.name)' NSG will now '$($ruleAfter.Access)' access to '$($ruleAfter.DestinationAddressPrefix)'"
}


# Ensure SRE is peered to correct mirror set
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Ensuring SRE is peered to correct mirror set..."
# We do this as the Tier of the DSG may have changed and we want to ensure we are peered
# to the correct mirror set fo its current Tier and not peered to the mirror set for
# any other Tier


# Unpeer any existing networks before (re-)establishing correct peering for DSG
# -----------------------------------------------------------------------------
Write-Host -ForegroundColor DarkCyan "Removing all existing mirror peerings..."
$dsgVnet = Get-AzVirtualNetwork -Name $config.dsg.network.vnet.name -ResourceGroupName $config.dsg.network.vnet.rg

# Get all mirror VNets from management subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
$mirrorVnets = Get-AzVirtualNetwork | Where-Object { $_.Name -Like "*PKG_MIRRORS*" }

# Remove SHM side of mirror peerings involving this SRE
ForEach($mirrorVnet in $mirrorVnets) {
    $mirrorPeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $mirrorVnet.Name -ResourceGroupName $mirrorVnet.ResourceGroupName
    ForEach($mirrorPeering in $mirrorPeerings) {
        # Remove peerings that involve this SRE
        If($mirrorPeering.RemoteVirtualNetwork.Id -eq $dsgVnet.Id) {
            Write-Host -ForegroundColor DarkCyan " [ ] Removing peering $($mirrorPeering.Name): $($mirrorPeering.VirtualNetworkName) <-> $($dsgVnet.Name)"
            $_ = Remove-AzVirtualNetworkPeering -Name $mirrorPeering.Name -VirtualNetworkName $mirrorVnet.Name -ResourceGroupName $mirrorVnet.ResourceGroupName -Force;
            if ($?) {
                Write-Host -ForegroundColor DarkGreen " [o] Peering removal succeeded"
            } else {
                Write-Host -ForegroundColor DarkRed " [x] Peering removal failed!"
            }
        }
    }
}

# Remove peering to this SRE from each SHM mirror network
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$dsgPeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $dsgVnet.Name -ResourceGroupName $dsgVnet.ResourceGroupName
Write-Host "dsgPeerings: $dsgPeerings"
ForEach($dsgPeering in $dsgPeerings) {
    # Remove peerings that involve any of the mirror VNets
    $peeredVnets = $mirrorVnets | Where-Object { $_.Id -eq $dsgPeering.RemoteVirtualNetwork.Id }
    ForEach($mirrorVnet in $peeredVnets) {
        Write-Host -ForegroundColor DarkCyan " [ ] Removing peering $($dsgPeering.Name): $($dsgPeering.VirtualNetworkName) <-> $($mirrorVnet.Name)"
        $_ = Remove-AzVirtualNetworkPeering -Name $dsgPeering.Name -VirtualNetworkName $dsgVnet.Name -ResourceGroupName $dsgVnet.ResourceGroupName -Force;
        if ($?) {
            Write-Host -ForegroundColor DarkGreen " [o] Peering removal succeeded"
        } else {
            Write-Host -ForegroundColor DarkRed " [x] Peering removal failed!"
        }
    }
}


# Re-peer to the correct network for this SRE
# -------------------------------------------
Write-Host -ForegroundColor DarkCyan "Peering to the correct mirror network..."
If(!$config.dsg.mirrors.vnet.name){
    Write-Host -ForegroundColor DarkGreen "No mirror VNet is configured for Tier $($config.dsg.tier) SRE $($config.dsg.id). Nothing to do."
} else {
    # Fetch mirror Vnet
    $_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
    $mirrorVnet = Get-AzVirtualNetwork -Name $config.dsg.mirrors.vnet.name -ResourceGroupName $config.shm.network.vnet.rg

    # Add peering to Mirror Vnet
    $params = @{
        "Name" = "PEER_" + $config.dsg.network.vnet.name
        "VirtualNetwork" = $mirrorVnet
        "RemoteVirtualNetworkId" = $dsgVnet.Id
        "BlockVirtualNetworkAccess" = $FALSE
        "AllowForwardedTraffic" = $FALSE
        "AllowGatewayTransit" = $FALSE
        "UseRemoteGateways" = $FALSE
    };
    Write-Host -ForegroundColor DarkCyan " [ ] Adding peering '$($params.Name)' to mirror VNet '$($params.VirtualNetwork.Name)'."
    $_ = Add-AzVirtualNetworkPeering @params;
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] Peering addition succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Peering addition failed!"
    }

    # Add Peering to SRE Vnet
    $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
    $params = @{
        "Name" = "PEER_" + $config.dsg.mirrors.vnet.name
        "VirtualNetwork" = $dsgVnet
        "RemoteVirtualNetworkId" = $mirrorVnet.Id
        "BlockVirtualNetworkAccess" = $FALSE
        "AllowForwardedTraffic" = $FALSE
        "AllowGatewayTransit" = $FALSE
        "UseRemoteGateways" = $FALSE
    };
    Write-Host -ForegroundColor DarkCyan " [ ] Adding peering '$($params.Name)' to SRE VNet '$($params.VirtualNetwork.Name)'."
    $_ = Add-AzVirtualNetworkPeering @params;
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] Peering addition succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Peering addition failed!"
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
