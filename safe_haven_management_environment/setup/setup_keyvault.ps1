param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
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

# Add group access and remove user access
Set-AzKeyVaultAccessPolicy -VaultName $config.keyVault.name -ObjectId (Get-AzADGroup -SearchString $config.adminSecurityGroupName)[0].Id -PermissionsToKeys Get, List, Update, Create, Import, Delete, Backup, Restore, Recover -PermissionsToSecrets Get, List, Set, Delete, Recover, Backup, Restore -PermissionsToCertificates Get, List, Delete, Create, Import, Update, Managecontacts, Getissuers, Listissuers, Setissuers, Deleteissuers, Manageissuers, Recover, Backup, Restore
Remove-AzKeyVaultAccessPolicy -VaultName $config.keyVault.name -UserPrincipalName (Get-AzContext).Account.Id

# Switch back to original subscription
Set-AzContext -Context $prevContext;