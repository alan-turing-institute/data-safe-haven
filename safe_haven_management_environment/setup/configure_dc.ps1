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

# Fetch ADSync user password
$adsyncPassword = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name -secretName $config.keyVault.secretNames.adsyncPassword
$adsyncAccountPasswordEncrypted = ConvertTo-SecureString $adsyncPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)

# Fetch DC/NPS admin username
$dcNpsAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name -secretName $config.keyVault.secretNames.dcNpsAdminUsername -defaultValue "shm$($config.id)admin".ToLower()

# Run configuration script remotely
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "dc" "remote" "Active_Directory_Configuration.ps1"
$params = @{
  oubackuppath = "`"C:\Scripts\GPOs`""
  domainou = "`"$($config.domain.dn)`""
  domain = "`"$($config.domain.fqdn)`""
  identitySubnetCidr = "`"$($config.network.subnets.identity.cidr)`""
  webSubnetCidr = "`"$($config.network.subnets.web.cidr)`""
  serverName = "`"$($config.dc.vmName)`""
  serverAdminName = "`"$dcNpsAdminUsername`""
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
