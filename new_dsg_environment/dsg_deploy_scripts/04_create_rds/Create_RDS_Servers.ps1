param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Admin user credentials (must be same as for DSG DC for now)
$adminUser = $config.dsg.dc.admin.username
$adminPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.dc.admin.passwordSecretName).SecretValueText

# VM sizes
$rdsGatewayVmSize = "Standard_DS2_v2"
$rdsHostVmSize = "Standard_DS2_v2"

$params = @{
 "RDS Gateway Name" = $config.rds.gateway.vmName
 "RDS Gateway VM Size" = $rdsGatewayVmSize
 "RDS Gateway IP Address" = $config.rds.gateway.vmName
 "RDS Session Host 1 Name" = $config.rds.sessionHost1.vmName
 "RDS Session Host 1 VM Size" = $rdsHostVmSize
 "RDS Session Host 1 IP Address" = $config.rds.sessionHost1.ip 
 "RDS Session Host 2 Name" = $config.rds.sessionHost2.vmName
 "RDS Session Host 2 VM Size" = $rdsHostVmSize
 "RDS Session Host 2 IP Address" = $config.rds.sessionHost2.ip
 "Administrator User" = $adminUser
 "Administrator Password" = (ConvertTo-SecureString $adminPassword -AsPlainText -Force)
 "Virtual Network Name" = $config.dsg.network.vnet.name
 "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
 "Virtual Network Subnet" = $config.dsg.network.subnets.rds.name
 "Domain Name" = $config.dsg.domain.fqdn
}

Write-Output $params

$templatePath = Join-Path $PSScriptRoot "rds-master-template.json"

New-AzResourceGroup -Name $config.rds.rg  -Location uksouth
New-AzResourceGroupDeployment -ResourceGroupName $config.rds.rg `
  -TemplateFile $templatePath  @params -Verbose
