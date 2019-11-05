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

$vmSize = "Standard_B2ms"

$params = @{
"Data Server Name" = $config.dsg.dataserver.vmName
"Domain Name" = $config.dsg.domain.fqdn
"VM Size" = $vmSize
"IP Address" = $config.dsg.dataserver.ip
"Administrator User" = $adminUsername
"Administrator Password" = (ConvertTo-SecureString $adminPassword -AsPlainText -Force)
"Virtual Network Name" = $config.dsg.network.vnet.name
"Virtual Network Resource Group" = $config.dsg.network.vnet.rg
"Virtual Network Subnet" = $config.dsg.network.subnets.data.name
}

Write-Output $params

# Deploy data server template
$templatePath = Join-Path $PSScriptRoot "dataserver-master-template.json"
$_ = New-AzResourceGroup -Name $config.dsg.dataserver.rg -Location $config.dsg.location
New-AzResourceGroupDeployment -ResourceGroupName  $config.dsg.dataserver.rg `
  -TemplateFile $templatePath @params -Verbose

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;