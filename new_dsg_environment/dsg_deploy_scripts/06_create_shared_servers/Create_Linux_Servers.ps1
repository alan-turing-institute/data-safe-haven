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
$hackMdVmSize = "Standard_DS2_v2"
$gitlabVmSize = "Standard_DS2_v2"

$params = @{
"GITLab Server Name" = $config.linux.gitlab.vmName
"GITLab VM Size" = $gitlabVMSize
"GITLab IP Address" =  $config.linux.gitlab.ip 
"HACKMD Server Name" = $config.linux.hackmd.vmName
"HACKMD VM Size" = $hackmdVMSize
"HACKMD IP Address" = $config.linux.hackmd.ip
"Administrator User" = $adminUser
"Administrator Password" = (ConvertTo-SecureString $adminPassword -AsPlainText -Force)
"Virtual Network Name" = $config.dsg.network.vnet.name
"Virtual Network Resource Group" = $config.dsg.network.vnet.rg
"Virtual Network Subnet" = $config.dsg.network.subnets.data.name
}

Write-Output $params

$templatePath = Join-Path $PSScriptRoot "inux-master-template.json"

New-AzResourceGroupDeployment -ResourceGroupName $config.linux.rg `
  -TemplateFile $templatePath @params -Verbose
