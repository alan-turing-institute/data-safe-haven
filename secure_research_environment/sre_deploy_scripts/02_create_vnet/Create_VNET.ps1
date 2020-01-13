param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force

# Get SRE config
$config = Get-SreConfig($sreId);
$originalContext = Get-AzContext

# Switch to SRE subscription
# --------------------------
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;


# Create VNet from template
# -------------------------
Write-Host -ForegroundColor DarkCyan "Creating virtual network '$($config.dsg.network.vnet.name)' from template..."
$templateName = "vnet-master-template"
New-AzResourceGroup -Name $config.dsg.network.vnet.rg -Location $config.dsg.location
$params = @{
    "Virtual Network Name" = $config.dsg.network.vnet.name
    "P2S VPN Certificate" = (Get-AzKeyVaultSecret -Name $config.shm.keyVault.secretNames.vpnCaCertificatePlain -VaultName $config.shm.keyVault.name).SecretValue
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
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.network.vnet.rg -TemplateFile $(Join-Path $PSScriptRoot "$($templateName).json") @params -Verbose
$result = $?
LogTemplateOutput -ResourceGroupName $config.dsg.network.vnet.rg -DeploymentName $templateName
if ($result) {
  Write-Host -ForegroundColor DarkGreen " [o] Template deployment succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Template deployment failed!"
  throw "Template deployment has failed. Please check the error message above before re-running this script."
}

# Fetch VNet information
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$dsgVnet = Get-AzVirtualNetwork -Name $config.dsg.network.vnet.name -ResourceGroupName $config.dsg.network.vnet.rg
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
$shmVnet = Get-AzVirtualNetwork -Name $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg


# Add Peering to SHM Vnet
# -----------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
Write-Host -ForegroundColor DarkCyan "Peering virtual network '$($config.dsg.network.vnet.name)' to $($config.shm.network.vnet.name)..."
$params = @{
    "Name" = "PEER_" + $config.dsg.network.vnet.name
    "VirtualNetwork" = $shmVnet
    "RemoteVirtualNetworkId" = $dsgVnet.Id
    "BlockVirtualNetworkAccess" = $FALSE
    "AllowForwardedTraffic" = $FALSE
    "AllowGatewayTransit" = $FALSE
    "UseRemoteGateways" = $FALSE
}
Add-AzVirtualNetworkPeering @params
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# Add peering to SRE VNet
# -----------------------
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
Write-Host -ForegroundColor DarkCyan "Peering virtual network '$($config.shm.network.vnet.name)' to $($config.dsg.network.vnet.name)..."
$params = @{
    "Name" = "PEER_" + $config.shm.network.vnet.name
    "VirtualNetwork" = $dsgVnet
    "RemoteVirtualNetworkId" = $shmVnet.Id
    "BlockVirtualNetworkAccess" = $FALSE
    "AllowForwardedTraffic" = $FALSE
    "AllowGatewayTransit" = $FALSE
    "UseRemoteGateways" = $FALSE
}
Add-AzVirtualNetworkPeering @params
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
