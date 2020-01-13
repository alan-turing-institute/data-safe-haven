# param(
#   [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
#   [string]$dsgId
# )

# Import-Module Az
# Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# # Get DSG config
# $config = Get-SreConfig($dsgId);

# # Unpeer any existing networks before (re-)establishing correct peering for DSG
# $unpeeringScriptPath = (Join-Path $PSScriptRoot "Unpeer_Dsg_And_Mirror_Networks.ps1"  -Resolve)

# # (Re-)configure Mirror peering for the DSG
# Write-Host ("Removing all existing mirror peerings")
# Invoke-Expression -Command "$unpeeringScriptPath -dsgId $dsgId";

# # Temporarily switch to DSG subscription
# $prevContext = Get-AzContext;
# $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# # Fetch DSG Vnet
# $dsgVnet = Get-AzVirtualNetwork -Name $config.dsg.network.vnet.name `
#                                 -ResourceGroupName $config.dsg.network.vnet.rg;

# # Temporarily switch to management subscription
# $_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
# # Check a mirror set has been configured for the DSG
# If(!$config.dsg.mirrors.vnet.name){
#   Write-Output ("No mirror VNet configured for Tier " + $config.dsg.tier + " DSG " `
#                 + $config.dsg.id + ". Nothing to do.")
#   Exit 0
# }
# # Fetch Mirrors Vnet
# $mirrorVnet = Get-AzVirtualNetwork -Name $config.dsg.mirrors.vnet.name `
#                                    -ResourceGroupName $config.shm.network.vnet.rg
# # Add Peering to Mirror Vnet
# $mirrorPeeringParams = @{
#   "Name" = "PEER_" + $config.dsg.network.vnet.name
#   "VirtualNetwork" = $mirrorVnet
#   "RemoteVirtualNetworkId" = $dsgVnet.Id
#   "BlockVirtualNetworkAccess" = $FALSE
#   "AllowForwardedTraffic" = $FALSE
#   "AllowGatewayTransit" = $FALSE
#   "UseRemoteGateways" = $FALSE
# };
# Write-Output ("Adding peering '" + $mirrorPeeringParams.Name `
#               + "' on mirror VNet '" + $mirrorPeeringParams.VirtualNetwork.Name + "'.")
# $_ = Add-AzVirtualNetworkPeering @mirrorPeeringParams;

# # Switch back to DSG subscription
# $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
# # Add Peering to DSG Vnet
# $dsgPeeringParams = @{
#   "Name" = "PEER_" + $config.dsg.mirrors.vnet.name
#   "VirtualNetwork" = $dsgVnet
#   "RemoteVirtualNetworkId" = $mirrorVnet.Id
#   "BlockVirtualNetworkAccess" = $FALSE
#   "AllowForwardedTraffic" = $FALSE
#   "AllowGatewayTransit" = $FALSE
#   "UseRemoteGateways" = $FALSE
# };
# Write-Output ("Adding peering '" + $dsgPeeringParams.Name `
#               + "' on DSG VNet '" + $dsgPeeringParams.VirtualNetwork.Name + "'.")
# $_ = Add-AzVirtualNetworkPeering @dsgPeeringParams;

# # Switch back to original subscription
# $_ = Set-AzContext -Context $prevContext;
