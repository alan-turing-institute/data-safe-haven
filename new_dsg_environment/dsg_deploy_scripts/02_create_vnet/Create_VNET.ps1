param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Get P2S Root certificate for VNet Gateway
$cert = (Get-AzKeyVaultSecret -Name $config.shm.keyVault.secretNames.vpnCaCertificatePlain -VaultName $config.shm.keyVault.name).SecretValue

$vnetCreateParams = @{
 "Virtual Network Name" = $config.dsg.network.vnet.name
 "P2S VPN Certificate" = $cert
 "Virtual Network Address Space" = $config.dsg.network.vnet.cidr
 "Subnet-Identity Address Prefix" = $config.dsg.network.subnets.identity.cidr
 "Subnet-RDS Address Prefix" = $config.dsg.network.subnets.rds.cidr
 "Subnet-Data Address Prefix" = $config.dsg.network.subnets.data.cidr
 "GatewaySubnet Address Prefix" = $config.dsg.network.subnets.gateway.cidr
 "Subnet-Identity Name" = $config.dsg.network.subnets.identity.name
 "Subnet-RDS Name" = $config.dsg.network.subnets.rds.name
 "Subnet-Data Name" = $config.dsg.network.subnets.data.name
 "GatewaySubnet Name" = $config.dsg.network.subnets.gateway.name
 "DNS Server IP Address" =  $config.dsg.dc.ip
}

Write-Output $vnetCreateParams

$templatePath = Join-Path $PSScriptRoot "vnet-master-template.json"

New-AzResourceGroup -Name $config.dsg.network.vnet.rg -Location $config.dsg.location
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.network.vnet.rg `
  -TemplateFile $templatePath @vnetCreateParams -Verbose

# Fetch DSG Vnet
$dsgVnet = Get-AzVirtualNetwork -Name $config.dsg.network.vnet.name `
                                -ResourceGroupName $config.dsg.network.vnet.rg

# Temporarily switch to management subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
# Fetch SHM Vnet
$shmVnet = Get-AzVirtualNetwork -Name $config.shm.network.vnet.name `
                                -ResourceGroupName $config.shm.network.vnet.rg
# Add Peering to SHM Vnet
$shmPeeringParams = @{
  "Name" = "PEER_" + $config.dsg.network.vnet.name
  "VirtualNetwork" = $shmVnet
  "RemoteVirtualNetworkId" = $dsgVnet.Id
  "BlockVirtualNetworkAccess" = $FALSE
  "AllowForwardedTraffic" = $FALSE
  "AllowGatewayTransit" = $FALSE
  "UseRemoteGateways" = $FALSE
}
Write-Output $shmPeeringParams
Add-AzVirtualNetworkPeering @shmPeeringParams

# Switch back to DSG subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
# Add Peering to DSG Vnet
$dsgPeeringParams = @{
  "Name" = "PEER_" + $config.shm.network.vnet.name
  "VirtualNetwork" = $dsgVnet
  "RemoteVirtualNetworkId" = $shmVnet.Id
  "BlockVirtualNetworkAccess" = $FALSE
  "AllowForwardedTraffic" = $FALSE
  "AllowGatewayTransit" = $FALSE
  "UseRemoteGateways" = $FALSE
}
Write-Output $dsgPeeringParams
Add-AzVirtualNetworkPeering @dsgPeeringParams

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
