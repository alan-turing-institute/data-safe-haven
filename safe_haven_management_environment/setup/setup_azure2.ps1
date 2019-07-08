param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-ShmFullConfig($shmId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;

$DCRootPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dc).SecretValueText;
New-AzResourceGroupDeployment -resourcegroupname $config.nps.rg`
        -templatefile "../arm_templates/shmnps/shmnps-template.json"`
        -Administrator_User atiadmin `
        -Administrator_Password (ConvertTo-SecureString $DCRootPassword -AsPlainText -Force) `
        -Virtual_Network_Resource_Group $config.network.vnet.rg `
        -Domain_Name $config.domain.fqdn;

# Switch back to original subscription
Set-AzContext -Context $prevContext;