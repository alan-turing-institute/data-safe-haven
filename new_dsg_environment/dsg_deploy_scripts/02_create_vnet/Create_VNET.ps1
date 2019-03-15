param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId)
# Get P2S Root certificate for VNet Gateway
$cert = (Get-AzKeyVaultSecret -Name $config.shm.keyVault.secretNames.p2sRootCert -VaultName $config.shm.keyVault.name).SecretValue

$params = @{
 "Virtual Network Name" = $config.dsg.network.vnet.name
 "P2S VPN Certificate" = $cert
 "Virtual Network Address Space" = $config.dsg.network.vnet.cidr
 "Subnet-Identity Address Prefix" = $config.dsg.network.subnets.identity.cidr
 "Subnet-RDS Address Prefix" = $config.dsg.network.subnets.rds.cidr 
 "Subnet-Data Address Prefix" = $config.dsg.network.subnets.data.cidr 
 "Subnet-Gateway Address Prefix" = $config.dsg.network.subnets.gateway.cidr
 "DNS Server IP Address" =  $config.dsg.dc.ip
}

Write-Output $params
New-AzResourceGroup -Name $config.dsg.network.vnet.rg -Location uksouth
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.network.vnet.rg `
  -TemplateFile vnet-master-template.json @params -Verbose
