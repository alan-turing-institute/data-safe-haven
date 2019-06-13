param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext;
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Fetch DSG Vnet
$dsgVnet = Get-AzVirtualNetwork -Name $config.dsg.network.vnet.name `
                                -ResourceGroupName $config.dsg.network.vnet.rg;

# Temporarily switch to management subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
# Fetch Mirrors Vnet
$mirrorVnet = Get-AzVirtualNetwork -Name $config.dsg.mirrors.vnet.name `
                                   -ResourceGroupName $config.dsg.mirrors.rg
# Add Peering to Mirror Vnet
$mirrorPeeringParams = @{
  "Name" = "PEER_" + $config.dsg.network.vnet.name
  "VirtualNetwork" = $mirrorVnet
  "RemoteVirtualNetworkId" = $dsgVnet.Id
  "BlockVirtualNetworkAccess" = $FALSE
  "AllowForwardedTraffic" = $FALSE
  "AllowGatewayTransit" = $FALSE
  "UseRemoteGateways" = $FALSE
};
Write-Output ("Adding peering '" + $mirrorPeeringParams.Name `
              + "' on mirror VNet '" + $mirrorPeeringParams.VirtualNetwork.Name + "'.")
$_ = Add-AzVirtualNetworkPeering @mirrorPeeringParams;

# Switch back to DSG subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
# Add Peering to DSG Vnet
$dsgPeeringParams = @{
  "Name" = "PEER_" + $config.dsg.mirrors.vnet.name
  "VirtualNetwork" = $dsgVnet
  "RemoteVirtualNetworkId" = $mirrorVnet.Id
  "BlockVirtualNetworkAccess" = $FALSE
  "AllowForwardedTraffic" = $FALSE
  "AllowGatewayTransit" = $FALSE
  "UseRemoteGateways" = $FALSE
};
Write-Output ("Adding peering '" + $dsgPeeringParams.Name `
              + "' on DSG VNet '" + $dsgPeeringParams.VirtualNetwork.Name + "'.")
$_ = Add-AzVirtualNetworkPeering @dsgPeeringParams;

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
