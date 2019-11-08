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
# For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# results in the double quotes in the JSON string being stripped in transit
# Escaping these with a single backslash retains the double quotes but the transferred
# string is truncated. Escaping these with backticks still results in the double quotes
# being stripped in transit, but we can then replace the backticks with double quotes
# at the other end to recover a valid JSON string.
$configJson = ($config | ConvertTo-Json -depth 10 -Compress).Replace("`"","```"")

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;

# Set paths to local scripts
$scriptPathSetOSLanguage = Join-Path $PSScriptRoot ".." "scripts" "dc" "local" "Set_OS_Language.ps1"
$scriptPathExtractRemoteScripts = Join-Path $PSScriptRoot ".." "scripts" "dc" "local" "Extract_Remote_Scripts.ps1"
$scriptPathADConfiguration = Join-Path $PSScriptRoot ".." "scripts" "dc" "local" "Active_Directory_Configuration.ps1"


# Extract configuration scripts remotely
Write-Host "Extracting configuration scripts for: $($config.dc.vmName)"
# Get list of blobs in the storage account
$storageAccount = Get-AzStorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
$storageContainerName = "dc_scripts"
$blobs = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context
$blobNames = $blobs | ForEach-Object{$_.Name}
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName `
                    -resourceGroup $config.storage.artifacts.rg -accountName $config.storage.artifacts.accountName `
                    -service Blob,File -resourceType Service,Container,Object `
                    -permission "rl" -validityHours 2;
# $pipeSeparatedBlobNames = $blobNames -join "|"
$params = @{
  remoteDir = "C:\Scripts"
  pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
  storageAccountName = "`"$($config.storage.artifacts.accountName)`""
  storageContainerName = "`"$storageContainerName`""
  sasToken = "`"$artifactSasToken`""
};
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPathExtractRemoteScripts `
    -Parameter $params
Write-Output $result.Value;

# Run Set_OS_Language.ps1 remotely
Write-Host "Setting OS language for: $($config.dc.vmName)"
$result1= Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPathSetOSLanguage;
Write-Output $result1.Value;


# Fetch ADSync user password (or create if not present)
$ADSyncPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.adsyncPassword).SecretValueText;
if ($null -eq $ADSyncPassword ) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $secretValue = New-Password;
  $secretValue = (ConvertTo-SecureString $secretValue -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.adsyncPassword -SecretValue $secretValue;
  $ADSyncPassword  = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.adsyncPassword ).SecretValueText
}

# Configure Active Directly remotely
Write-Host "Configuring Active Directory for: $($config.dc.vmName)"
$params = @{
  oubackuppath = "`"C:/Scripts/GPOs`""
  domainou = "`"$($config.domain.dn)`""
  domain = "`"$($config.domain.fqdn)`""
  serverName = "`"$($config.dc.vmName)`""
  adsyncAccountPassword = "`"$ADSyncPassword`""
}
$result3 = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPathADConfiguration `
    -Parameter $params;
Write-Output $result3.Value;







# Run SActive_Directory_Configuration.ps1 remotely
# THIS ISNT WORKING. RUN BY LOGGING INTO VM UNTILL FIXED
# $oubackuppath= "`"C:/Scripts/GPOs`""

# $params = @{
#   configJson = $configJson
#   adsyncpassword = "`"$ADSyncPassword`""
#   oubackuppath = "`"$oubackuppath`""
# }

# $result3 = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg `
#                 -Name SHMDC1 `
#                 -CommandId 'RunPowerShellScript'`
#                 -ScriptPath $scriptPathADConfiguration `
#                 -Parameter $params;

# Write-Output $result3.Value;


# Execute Set_OS_Language.ps1 on second DC
Write-Host "Setting OS language for: $($config.dcb.vmName)"
$result4= Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dcb.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPathSetOSLanguage;

Write-Output $result4.Value;

# Switch back to previous subscription
Set-AzContext -Context $prevContext;

