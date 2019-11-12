param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GenerateSasToken.psm1 -Force

# Get DSG config
# --------------
$config = Get-ShmFullConfig($shmId)
# # For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# # results in the double quotes in the JSON string being stripped in transit
# # Escaping these with a single backslash retains the double quotes but the transferred
# # string is truncated. Escaping these with backticks still results in the double quotes
# # being stripped in transit, but we can then replace the backticks with double quotes
# # at the other end to recover a valid JSON string.
# $configJson = ($config | ConvertTo-Json -depth 10 -Compress).Replace("`"","```"")

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;


# Import artifacts from blob storage
# ----------------------------------
Write-Host "Import configuration artifacts for: $($config.dc.vmName)"

# Get list of blobs in the storage account
$storageAccount = Get-AzStorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
$storageContainerName = "dcconfiguration"
$blobNames = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context | ForEach-Object{$_.Name}
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -accountName $config.storage.artifacts.accountName;

# Run import script remotely
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "dc" "remote" "Import_Artifacts.ps1" -Resolve
$params = @{
  remoteDir = "`"C:\Installation`""
  pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
  storageAccountName = "`"$($config.storage.artifacts.accountName)`""
  storageContainerName = "`"$storageContainerName`""
  sasToken = "`"$artifactSasToken`""
}
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
          -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Configure Active Directory remotely
# -----------------------------------
Write-Host "Configure Active Directory for: $($config.dc.vmName)"

# Fetch ADSync user password (or create if not present)
$adsyncPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.adsyncPassword).SecretValueText;
if ($null -eq $adsyncPassword ) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $secretValue = New-Password;
  $secretValue = (ConvertTo-SecureString $secretValue -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.adsyncPassword -SecretValue $secretValue;
  $adsyncPassword = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.adsyncPassword ).SecretValueText
}
$adsyncAccountPasswordEncrypted = ConvertTo-SecureString $adsyncPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)

# Fetch DC admin username (or create if not present)
$dcAdminUsername = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcAdminUsername).SecretValueText;
if ($null -eq $dcAdminUsername) {
  # Create secret locally but round trip via KeyVault to ensure it is successfully stored
  $secretValue = "shm$($config.id)admin".ToLower()
  $secretValue = (ConvertTo-SecureString $secretValue -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dcAdminUsername -SecretValue $secretValue;
  $dcAdminUsername = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dcAdminUsername ).SecretValueText;
}

# Run configuration script remotely
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "dc" "remote" "Active_Directory_Configuration.ps1"
$params = @{
  oubackuppath = "`"C:\Scripts\GPOs`""
  domainou = "`"$($config.domain.dn)`""
  domain = "`"$($config.domain.fqdn)`""
  identitySubnetCidr = "`"$($config.network.subnets.identity.cidr)`""
  webSubnetCidr = "`"$($config.network.subnets.web.cidr)`""
  serverName = "`"$($config.dc.vmName)`""
  serverAdminName = "`"$dcAdminUsername`""
  adsyncAccountPasswordEncrypted = "`"$adsyncAccountPasswordEncrypted`""
}
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
          -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Set the OS language to en-GB remotely
# -------------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "dc" "remote" "Set_OS_Language.ps1"

# Run on the primary DC
Write-Host "Setting OS language for: $($config.dc.vmName)"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
          -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
Write-Output $result.Value;

# Run on the secondary DC
Write-Host "Setting OS language for: $($config.dcb.vmName)"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dcb.vmName `
          -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
Write-Output $result.Value;


# Configure group policies
# ------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "dc" "remote" "Configure_Group_Policies.ps1"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
          -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
Write-Output $result.Value;


# Active directory delegation
# ---------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "dc" "remote" "Active_Directory_Delegation.ps1"
$params = @{
  netbiosName = "`"$($config.domain.netbiosName)`""
  ldapUsersGroup = "`"$($config.domain.securityGroups.dsvmLdapUsers.name)`""
}
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
          -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Switch back to previous subscription
# ------------------------------------
Set-AzContext -Context $prevContext;
