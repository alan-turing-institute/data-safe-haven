param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId)

$virtualNetworkName = "DSG_DSGROUP" + $dsgId + "_VNET1"
$addressSpacePrefix = $addressSpacePrefix12 + "." + $addressSpacePrefix3
$virtualNetworkAddressSpace = $addressSpacePrefix + ".0/21"
$subnetIdentityPrefix = $addressSpacePrefix + ".0/24"
$subnetRdsPrefix = $addressSpacePrefix12 + "." + ([int]$addressSpacePrefix3 + 1) + ".0/24"
$subnetDataPrefix = $addressSpacePrefix12 + "." + ([int]$addressSpacePrefix3 + 2) + ".0/24"
$subnetGatewayPrefix =  $addressSpacePrefix12 + "." + ([int]$addressSpacePrefix3 + 7) + ".0/27"
$dnsServerIP =  $addressSpacePrefix + ".250"
$cert = (Get-AzKeyVaultSecret -Name "sh-management-p2s-root-cert" -VaultName "dsg-management-test").SecretValue

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
