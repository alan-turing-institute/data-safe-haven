param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config and store original subscription
$config = Get-DsgConfig($dsgId);
$originalSubscription = Get-AzContext;

# Switch to DSG subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
# Get DSG VNet
$dsgVnet = Get-AzVirtualNetwork -Name $config.dsg.network.vnet.name -ResourceGroupName $config.dsg.network.vnet.rg

# Switch to management subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
# Get all VNets in Mirror resource group
$mirrorVnets = Get-AzVirtualNetwork -Name "*" -ResourceGroupName $config.dsg.mirrors.vnet.rg

# === Remove mirror side of peerings involving this DSG ===
Write-Output ("Removing peering for DSG network from SHM Mirror networks")
# Iterate over mirror VNets
@($mirrorVnets) | ForEach-Object{
  $mirrorPeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $_.Name  -ResourceGroupName $config.dsg.mirrors.vnet.rg;
  $mirrorVnet = $_
  # Iterate over peerings
  @($mirrorPeerings) | ForEach-Object{
    $mirrorPeering = $_
    # Remove peerings that involve this DSG
    If($mirrorPeering.RemoteVirtualNetwork.Id -eq $dsgVnet.Id) {
      Write-Output ("  - Removing peering " + $mirrorPeering.Name + " (linking " `
                    + $mirrorPeering.VirtualNetworkName + " to " + $dsgVnet.Name + ")")
      $_ = Remove-AzVirtualNetworkPeering -Name $mirrorPeering.Name -VirtualNetworkName $mirrorVnet.Name -ResourceGroupName $config.dsg.mirrors.vnet.rg -Force;
    }
  }
}

# Switch to DSG subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# === Remove mirror side of peerings involving this DSG ===
Write-Output ("Removing peering for SHM Mirror networks from DSG network")
$dsgPeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $dsgVnet.Name  -ResourceGroupName $config.dsg.network.vnet.rg;
# Iterate over peerings
@($dsgPeerings) | ForEach-Object{
  $dsgPeering = $_
  # Remove peerings that involve any of the mirror VNets
  If($dsgPeering.RemoteVirtualNetwork.Id -in (@($mirrorVnets) | ForEach-Object{$_.Id})) {
    Write-Output ("  - Removing peering " + $dsgPeering.Name + " (linking " `
                  + $dsgPeering.VirtualNetworkName + " to " + $dsgVnet.Name + ")")
    $_ = Remove-AzVirtualNetworkPeering -Name $dsgPeering.Name -VirtualNetworkName $dsgVnet.Name -ResourceGroupName $config.dsg.network.vnet.rg -Force;
  }
}

# Switch back to original subscription
$_ = Set-AzContext -Context $originalSubscription;
