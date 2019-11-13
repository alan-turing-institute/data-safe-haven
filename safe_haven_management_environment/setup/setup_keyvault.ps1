param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/GenerateSasToken.psm1 -Force

# Get SHM config
# --------------
$config = Get-ShmFullConfig($shmId)


# Temporarily switch to SHM subscription
# --------------------------------------
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;


# Create Resource Groups
# ----------------------
New-AzResourceGroup -Name $config.keyVault.rg  -Location $config.location -Force


# Ensure the keyvault exists
# --------------------------
$keyVault = Get-AzKeyVault -VaultName $config.keyVault.name -ResourceGroupName $config.keyVault.rg
if ($keyVault -ne $null) {
  Write-Host " [o] key vault $($config.keyVault.name) already exists"
} else {
  New-AzKeyVault -Name $config.keyVault.name  -ResourceGroupName $config.keyVault.rg -Location $config.location
  if ($?) {
    Write-Host " [o] Created key vault $($config.keyVault.name)"
  } else {
    Write-Host " [x] Failed to create key vault $($config.keyVault.name)!"
  }
}

# Add group access and remove user access
Set-AzKeyVaultAccessPolicy -VaultName $config.keyVault.name -ObjectId (Get-AzADGroup -SearchString $config.adminSecurityGroupName)[0].Id -PermissionsToKeys Get, List, Update, Create, Import, Delete, Backup, Restore, Recover -PermissionsToSecrets Get, List, Set, Delete, Recover, Backup, Restore -PermissionsToCertificates Get, List, Delete, Create, Import, Update, Managecontacts, Getissuers, Listissuers, Setissuers, Deleteissuers, Manageissuers, Recover, Backup, Restore
Remove-AzKeyVaultAccessPolicy -VaultName $config.keyVault.name -UserPrincipalName (Get-AzContext).Account.Id


# Ensure that secrets exist in the keyvault
# -----------------------------------------
# :: AAD Global Administrator password
$aadAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name `
                                         -secretName $config.keyVault.secretNames.aadAdminPassword

# :: DC/NPS admin username
$dcNpsAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name `
                                           -secretName $config.keyVault.secretNames.dcNpsAdminUsername `
                                           -defaultValue "shm$($config.id)admin".ToLower()

# :: DC/NPS admin password
$dcNpsAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name `
                                             -secretName $config.keyVault.secretNames.dcNpsAdminPassword

# :: DC safe mode password
$dcSafemodePassword = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name `
                                             -secretName $config.keyVault.secretNames.dcSafemodePassword


# Switch back to original subscription
# ------------------------------------
Set-AzContext -Context $prevContext;