param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Admin user credentials (must be same as for DSG DC for now)
$adminUsername = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.dsg.dc.usernameSecretName).SecretValueText;
$adminPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.dc.admin.passwordSecretName).SecretValueText

# VM sizes
$rdsGatewayVmSize = "Standard_B2ms"
$rdsHostVmSize = "Standard_DS2_v2"

$params = @{
 "RDS Gateway Name" = $config.dsg.rds.gateway.vmName
 "RDS Gateway VM Size" = $rdsGatewayVmSize
 "RDS Gateway IP Address" = $config.dsg.rds.gateway.ip
 "RDS Session Host 1 Name" = $config.dsg.rds.sessionHost1.vmName
 "RDS Session Host 1 VM Size" = $rdsHostVmSize
 "RDS Session Host 1 IP Address" = $config.dsg.rds.sessionHost1.ip
 "RDS Session Host 2 Name" = $config.dsg.rds.sessionHost2.vmName
 "RDS Session Host 2 VM Size" = $rdsHostVmSize
 "RDS Session Host 2 IP Address" = $config.dsg.rds.sessionHost2.ip
 "Administrator User" = $adminUsername
 "Administrator Password" = (ConvertTo-SecureString $adminPassword -AsPlainText -Force)
 "Virtual Network Name" = $config.dsg.network.vnet.name
 "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
 "Virtual Network Subnet" = $config.dsg.network.subnets.rds.name
 "Domain Name" = $config.dsg.domain.fqdn
}

Write-Output $params

$templatePath = Join-Path $PSScriptRoot "rds-master-template.json"

New-AzResourceGroup -Name $config.dsg.rds.rg  -Location $config.dsg.location
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.rds.rg `
  -TemplateFile $templatePath  @params -Verbose

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;