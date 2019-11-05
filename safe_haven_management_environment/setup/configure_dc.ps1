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

# Run remote script
$scriptPath1 = Join-Path $PSScriptRoot ".." "scripts" "dc" "Set_OS_Language.ps1"
$scriptPath2 = Join-Path $PSScriptRoot ".." "scripts" "dc" "map_drive.ps1"
$scriptPath3 = Join-Path $PSScriptRoot ".." "scripts" "dc" "Active_Directory_Configuration.ps1"

# Fetch ADSync user password (or create if not present)
$ADSyncPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.adsyncPassword).SecretValueText;
if ($null -eq $ADSyncPassword ) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.adsyncPassword -SecretValue $newPassword;
  $ADSyncPassword  = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.adsyncPassword ).SecretValueText
}

# Run Set_OS_Language.ps1 remotely
$result1= Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath1;

Write-Output $result1.Value;


# Map drive to DC1-SHM-SHMID
$artifactLocation = "https://" + $config.storage.artifacts.accountName + ".blob.core.windows.net";
$artifactSasToken = New-AccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg `
  -accountName $config.storage.artifacts.accountName -service Blob,File -resourceType Service,Container,Object `
  -permission "rl" -validityHours 2;

$artifact_uri = $( $artifactLocation + "/scripts/SHM_DC.zip");

$params = @{
  uri = $artifact_uri
  sasToken= "`"$artifactSasToken`""
};

$result2 = Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg  -Name $config.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath2 `
    -Parameter $params;
    
Write-Output $result2.Value;


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
#                 -ScriptPath $scriptPath3 `
#                 -Parameter $params;

# Write-Output $result3.Value;


# Execute Set_OS_Language.ps1 on second DC
$result4= Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name $config.dcb.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath1;

Write-Output $result4.Value;

# Switch back to previous subscription
Set-AzContext -Context $prevContext;

