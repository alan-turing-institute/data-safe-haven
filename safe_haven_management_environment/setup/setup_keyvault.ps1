param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-ShmFullConfig($shmId)
$jsonOut = ($config | ConvertTo-Json -depth 10)
Write-Host $jsonOut

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

# # Ensure that AAD Global Administrator password exists
$aadAdminPassword = Ensure-Keyvault-Secret -keyvaultName $config.keyVault.name -secretName $config.keyVault.secretNames.dcAdminUsername -defaultValue "shm$($config.id)admin".ToLower()
# $aadAdminPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcAdminUsername).SecretValueText;
# if ($null -eq $dcAdminUsername) {
#   # Create secret locally but round trip via KeyVault to ensure it is successfully stored
#   $secretValue = "shm$($config.id)admin".ToLower()
#   $secretValue = (ConvertTo-SecureString $secretValue -AsPlainText -Force);
#   $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dcAdminUsername -SecretValue $secretValue;
#   $dcAdminUsername = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dcAdminUsername ).SecretValueText;
# }

# Fetch DC admin username (or create if not present)
$dcAdminUsername = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcAdminUsername).SecretValueText;
if ($null -eq $dcAdminUsername) {
  # Create secret locally but round trip via KeyVault to ensure it is successfully stored
  $secretValue = "shm$($config.id)admin".ToLower()
  $secretValue = (ConvertTo-SecureString $secretValue -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dcAdminUsername -SecretValue $secretValue;
  $dcAdminUsername = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dcAdminUsername ).SecretValueText;
}

# Fetch DC admin user password (or create if not present)
$dcAdminPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcAdminPassword).SecretValueText;
if ($null -eq $dcAdminPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $secretValue = New-Password;
  $secretValue = (ConvertTo-SecureString $secretValue -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dcAdminPassword -SecretValue $secretValue;
  $dcAdminPassword = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dcAdminPassword ).SecretValueText;
}

# Fetch DC safe mode password (or create if not present)
$dcSafemodePassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcSafemodePassword).SecretValueText;
if ($null -eq $dcSafemodePassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $secretValue = New-Password;
  $secretValue = (ConvertTo-SecureString $secretValue -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dcSafemodePassword -SecretValue $secretValue;
  $dcSafemodePassword  = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dcSafemodePassword ).SecretValueText
}


# Switch back to original subscription
Set-AzContext -Context $prevContext;