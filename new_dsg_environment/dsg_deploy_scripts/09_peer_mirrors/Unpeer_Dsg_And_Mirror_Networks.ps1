param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config and store original subscription
$config = Get-DsgConfig($dsgId);
$originalSubscription = Get-AzContext;


# Switch to management subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
# Remove peering from mirror VNet
$mirrorPeeringParams = @{
  "Name" = "PEER_" + $config.dsg.network.vnet.name
  "VirtualNetworkName" = $config.dsg.mirrors.vnet.name
  "ResourceGroupName" = $config.dsg.mirrors.vnet.rg
};
Write-Output ("Removing peering '" + $mirrorPeeringParams.Name `
              + "' on mirror VNet '" + $mirrorPeeringParams.VirtualNetworkName + "'.")
$_ = Remove-AzVirtualNetworkPeering @mirrorPeeringParams -Force;


# Switch to DSG subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
# Remove peering from DSG VNet
$dsgPeeringParams = @{
  "Name" = "PEER_" + $config.dsg.mirrors.vnet.name
  "VirtualNetworkName" = $config.dsg.network.vnet.name
  "ResourceGroupName" = $config.dsg.network.vnet.rg
};
Write-Output ("Removing peering '" + $dsgPeeringParams.Name `
              + "' on DSG VNet '" + $dsgPeeringParams.VirtualNetworkName + "'.")
$_ = Remove-AzVirtualNetworkPeering @dsgPeeringParams -Force;


# Switch back to original subscription
$_ = Set-AzContext -Context $originalSubscription;
