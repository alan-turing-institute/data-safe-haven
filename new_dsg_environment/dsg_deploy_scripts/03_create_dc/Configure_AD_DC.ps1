param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/GenerateSasToken.psm1 -Force

# Get SRE config
# --------------
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext

# Set constants used in this script
# ---------------------------------
$artifactsFolderName = "dc-config-scripts"
$remoteUploadDir = "C:\Installation"
$storageAccountLocation = $config.dsg.location
$storageAccountName = $config.dsg.storage.artifacts.accountName
$storageAccountRg = $config.dsg.storage.artifacts.rg


# Switch to SRE subscription
# --------------------------
$storageAccountSubscription = $config.dsg.subscriptionName
$_ = Set-AzContext -SubscriptionId $storageAccountSubscription;

# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving user passwords..."
$dcAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()


# Setup storage account and upload artifacts
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Setting up storage account and uploading artifacts..."
New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
if ($notExists) {
  Write-Host -ForegroundColor DarkCyan "Creating storage account '$storageAccountName'..."
  $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_LRS" -Kind "StorageV2"
}
# Create blob storage containers
ForEach ($containerName in ($artifactsFolderName)) {
  if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
    Write-Host -ForegroundColor DarkCyan "Creating container '$containerName' in storage account '$storageAccountName'"
    New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
  }
}
# Upload artifacts for configuring the DC
Write-Host -ForegroundColor DarkCyan "Uploading DC configuration files to storage account '$storageAccountName'"
Set-AzStorageBlobContent -Container $artifactsFolderName -Context $storageAccount.Context -File "$PSScriptRoot/artifacts/$artifactsFolderName/GPOs.zip" -Force
Set-AzStorageBlobContent -Container $artifactsFolderName -Context $storageAccount.Context -File "$PSScriptRoot/artifacts/$artifactsFolderName/StartMenuLayoutModification.xml" -Force


# Import artifacts from blob storage
# ----------------------------------
Write-Host -ForegroundColor DarkCyan "Importing configuration artifacts for: $($config.dsg.dc.vmName)..."
# Get list of blobs in the storage account
$blobNames = Get-AzStorageBlob -Container $artifactsFolderName -Context $storageAccount.Context | ForEach-Object{$_.Name}
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.dsg.subscriptionName -resourceGroup $storageAccountRg -accountName $storageAccountName
# Run import script remotely
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Import_Artifacts.ps1"
$params = @{
  remoteDir = "`"$remoteUploadDir`""
  pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
  storageAccountName = "`"$storageAccountName`""
  storageContainerName = "`"$artifactsFolderName`""
  sasToken = "`"$artifactSasToken`""
}
$result = Invoke-AzVMRunCommand -Name $config.dsg.dc.vmName -ResourceGroupName $config.dsg.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Remotely set the OS language for the DC
# ---------------------------------------
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Set_OS_Locale.ps1"
Write-Host -ForegroundColor DarkCyan "Setting OS language for: $($config.dsg.dc.vmName)..."
$result = Invoke-AzVMRunCommand -Name $config.dsg.dc.vmName -ResourceGroupName $config.dsg.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
Write-Output $result.Value;


# Create users, groups and OUs
# ----------------------------
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Create_Users_Groups_OUs.ps1"
Write-Host -ForegroundColor DarkCyan "Creating users, groups and OUs for: $($config.dsg.dc.vmName)..."
$params = @{
  sreNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
  sreDn = "`"$($config.dsg.domain.dn)`""
  sreServerAdminSgName = "`"$($config.dsg.domain.securityGroups.serverAdmins.name)`""
  sreDcAdminUsername = "`"$($dcAdminUsername)`""
}
$result = Invoke-AzVMRunCommand -Name $config.dsg.dc.vmName -ResourceGroupName $config.dsg.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Configure DNS
# -------------
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_DNS.ps1"
Write-Host -ForegroundColor DarkCyan "Configuring DNS..."
$params = @{
  identitySubnetCidr = "`"$($config.dsg.network.subnets.identity.cidr)`""
  rdsSubnetCidr = "`"$($config.dsg.network.subnets.rds.cidr)`""
  dataSubnetCidr = "`"$($config.dsg.network.subnets.data.cidr)`""
  shmFqdn = "`"$($config.shm.domain.fqdn)`""
  shmDcIp = "`"$($config.shm.dc.ip)`""
}
$result = Invoke-AzVMRunCommand -Name $config.dsg.dc.vmName -ResourceGroupName $config.dsg.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Configure GPOs
# --------------
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_GPOs.ps1"
Write-Host -ForegroundColor DarkCyan "Configuring GPOs..."
$params = @{
  oubackuppath = "`"$remoteUploadDir\GPOs`""
  sreNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
  sreFqdn = "`"$($config.dsg.domain.fqdn)`""
  sreDomainOu = "`"$($config.dsg.domain.dn)`""
}
$result = Invoke-AzVMRunCommand -Name $config.dsg.dc.vmName -ResourceGroupName $config.dsg.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Restart the DC
# --------------
Write-Host "Restarting $config.dsg.dc.vmName"
Restart-AzureRmVM -Name $config.dsg.dc.vmName -ResourceGroupName $config.dsg.dc.rg


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
