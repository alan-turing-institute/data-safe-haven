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

# Temporarily switch to SHM subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;

# Create Resource Groups
New-AzResourceGroup -Name $config.keyVault.rg  -Location $config.location

# Create a keyvault
New-AzKeyVault -Name $config.keyVault.name  -ResourceGroupName $config.keyVault.rg -Location $config.location

Write-Host "Before running the next step, make sure to add a policy to the KeyVault '$($config.keyVault.name)' in the '$($config.keyVault.rg)' resource group that gives the administrator security group for this Safe Haven instance rights to manage Keys, Secrets and Certificates."
        
# Switch back to original subscription
Set-AzContext -Context $prevContext;