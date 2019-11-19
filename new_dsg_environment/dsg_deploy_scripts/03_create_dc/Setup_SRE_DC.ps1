param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/GenerateSasToken.psm1 -Force

# Get SRE config
# --------------
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext


# Set constants used in this script
# ---------------------------------
$artifactsFolderNameConfig = "sre-dc-configuration"
$artifactsFolderNameCreate = "sre-dc-ad-setup-scripts"
$remoteUploadDir = "C:\Installation"
$storageAccountLocation = $config.dsg.location
$storageAccountName = $config.dsg.storage.artifacts.accountName
$storageAccountRg = $config.dsg.storage.artifacts.rg
$storageAccountSubscription = $config.dsg.subscriptionName


# Switch to SRE subscription
# --------------------------
$_ = Set-AzContext -Subscription $storageAccountSubscription;


# Create storage account if it doesn't exist
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Ensuring that storage account '$storageAccountName' exists..."
$_ = New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force;
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
if($notExists) {
  Write-Host -ForegroundColor DarkCyan "Creating storage account '$storageAccountName'..."
  $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_GRS" -Kind "StorageV2"
}
# $artifactsFolderName = "dc-create-scripts"
# $artifactsDir = (Join-Path $PSScriptRoot "artifacts" $artifactsFolderName)
# $containerName = $artifactsFolderName
# Create container if it doesn't exist

# Create blob storage containers
ForEach ($containerName in ($artifactsFolderNameConfig, $artifactsFolderNameCreate)) {
  if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
    Write-Host -ForegroundColor DarkCyan "Creating container '$containerName' in storage account '$storageAccountName'..."
    $_ = New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
  }
  $blobs = @(Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context)
  $numBlobs = $blobs.Length
  if($numBlobs -gt 0){
    Write-Host -ForegroundColor DarkCyan "Deleting $numBlobs blobs aready in container '$containerName'..."
    $blobs | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $storageAccount.Context -Force}
    while($numBlobs -gt 0){
      Write-Host -ForegroundColor DarkCyan "Waiting for deletion of $numBlobs remaining blobs..."
      Start-Sleep -Seconds 10
      $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context).Length
    }
  }
}

# # Setup storage account and upload artifacts
# # ------------------------------------------
# Write-Host -ForegroundColor DarkCyan "Setting up storage account and uploading artifacts..."
# New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force
# $storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
# if ($notExists) {
#   Write-Host -ForegroundColor DarkCyan "Creating storage account '$storageAccountName'..."
#   $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_LRS" -Kind "StorageV2"
# }
# Create blob storage containers
# ForEach ($containerName in ($artifactsFolderName)) {
#   if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
#     Write-Host -ForegroundColor DarkCyan "Creating container '$containerName' in storage account '$storageAccountName'"
#     New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
#   }
# }

# Upload artifacts for configuring the DC
# ---------------------------------------
Write-Host -ForegroundColor DarkCyan "Uploading DC configuration files to storage account '$storageAccountName'..."

ForEach ($folderFilePair in (($artifactsFolderNameCreate, "dc-create.zip"),
                             ($artifactsFolderNameConfig, "GPOs.zip"),
                             ($artifactsFolderNameConfig, "StartMenuLayoutModification.xml"))) {

  $artifactsFolderName, $artifactsFileName = $folderFilePair
  Set-AzStorageBlobContent -Container $artifactsFolderName -Context $storageAccount.Context -File "$PSScriptRoot/artifacts/$artifactsFolderName/$artifactsFileName" -Force
  if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] Uploaded '$artifactsFileName'"
  } else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to upload '$artifactsFileName'!"
  }
}


# # $artifactsFolderName

# # Set-AzStorageBlobContent -Container $artifactsFolderName -Context $storageAccount.Context -File "$PSScriptRoot/artifacts/$artifactsFolderName/GPOs.zip" -Force
# # Set-AzStorageBlobContent -Container $artifactsFolderName -Context $storageAccount.Context -File "$PSScriptRoot/artifacts/$artifactsFolderName/StartMenuLayoutModification.xml" -Force


# # Upload ZIP file with artifacts
# Write-Host -ForegroundColor DarkCyan "Uploading artifacts to storage..."
# $zipFileName = "dc-create.zip"
# $zipFilePath = (Join-Path $artifactsDir $zipFileName )
# Write-Host -ForegroundColor DarkCyan " - Uploading '$zipFilePath' to container '$containerName'"
# $_ = Set-AzStorageBlobContent -File $zipFilePath -Container $containerName -Context $storageAccount.Context;
# if ($?) {
#   Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
# } else {
#   Write-Host -ForegroundColor DarkRed " [x] Failed!"
# }

# === Deploying DC from template ====
Write-Host -ForegroundColor DarkCyan "Deploying DC from template..."

# Get SAS token
Write-Host -ForegroundColor DarkCyan " - obtaining SAS token..."
$artifactLocation = "https://$storageAccountName.blob.core.windows.net/$artifactsFolderNameCreate/$zipFileName";
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $storageAccountSubscription -resourceGroup $storageAccountRg -accountName $storageAccountName

# Retrieve passwords from the keyvault
Write-Host -ForegroundColor DarkCyan " - creating/retrieving user passwords..."
$dcAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()
$dcAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminPassword

# Deploy template
$templateName = "dc-master-template"
Write-Host -ForegroundColor DarkCyan " - deploying template $templateName..."
$netbiosNameMaxLength = 15
if($config.dsg.domain.netbiosName.length -gt $netbiosNameMaxLength) {
  throw "NetBIOS name must be no more than 15 characters long. '$($config.dsg.domain.netbiosName)' is $($config.dsg.domain.netbiosName.length) characters long."
}
$params = @{
  "DC Name" = $config.dsg.dc.vmName
  "SRE ID" = $config.dsg.id
  "VM Size" = $config.dsg.dc.vmSize
  "IP Address" = $config.dsg.dc.ip
  "Administrator User" = $dcAdminUsername
  "Administrator Password" = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
  "Virtual Network Name" = $config.dsg.network.vnet.name
  "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
  "Virtual Network Subnet" = $config.dsg.network.subnets.identity.name
  "Artifacts Location" = $artifactLocation
  "Artifacts Location SAS Token" = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)
  "Domain Name" = $config.dsg.domain.fqdn
  "NetBIOS Name" = $config.dsg.domain.netbiosName
}
$_ = New-AzResourceGroup -Name $config.dsg.dc.rg -Location $config.dsg.location -Force
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.dc.rg -TemplateFile $(Join-Path $PSScriptRoot "$($templateName).json") @params -Verbose -DeploymentDebugLogLevel ResponseContent
$result = $?
LogTemplateOutput -ResourceGroupName $config.dsg.dc.rg -DeploymentName $templateName
if ($result) {
  Write-Host -ForegroundColor DarkGreen " [o] Template deployment succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Template deployment failed!"
}

# # Switch back to original subscription
# # ------------------------------------
# $_ = Set-AzContext -Context $originalContext;



# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving user passwords..."
$dcAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()


# # Setup storage account and upload artifacts
# # ------------------------------------------
# Write-Host -ForegroundColor DarkCyan "Setting up storage account and uploading artifacts..."
# New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force

# # $storageAccountLocation = $config.dsg.location
# $artifactsFolderName = "dc-config-scripts"
# $storageAccountName = $config.dsg.storage.artifacts.accountName
# $storageAccountRg = $config.dsg.storage.artifacts.rg
# $storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue

# if ($notExists) {
#   Write-Host -ForegroundColor DarkCyan "Creating storage account '$storageAccountName'..."
#   $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_LRS" -Kind "StorageV2"
# }
# # Create blob storage containers
# ForEach ($containerName in ($artifactsFolderName)) {
#   if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
#     Write-Host -ForegroundColor DarkCyan "Creating container '$containerName' in storage account '$storageAccountName'"
#     New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
#   }
# }
# # Upload artifacts for configuring the DC
# Write-Host -ForegroundColor DarkCyan "Uploading DC configuration files to storage account '$storageAccountName'"
# Set-AzStorageBlobContent -Container $artifactsFolderName -Context $storageAccount.Context -File "$PSScriptRoot/artifacts/$artifactsFolderName/GPOs.zip" -Force
# Set-AzStorageBlobContent -Container $artifactsFolderName -Context $storageAccount.Context -File "$PSScriptRoot/artifacts/$artifactsFolderName/StartMenuLayoutModification.xml" -Force


# Import artifacts from blob storage
# ----------------------------------
Write-Host -ForegroundColor DarkCyan "Importing configuration artifacts for: $($config.dsg.dc.vmName)..."
# Get list of blobs in the storage account
$blobNames = Get-AzStorageBlob -Container $artifactsFolderNameConfig -Context $storageAccount.Context | ForEach-Object{$_.Name}
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.dsg.subscriptionName -resourceGroup $storageAccountRg -accountName $storageAccountName
# Run import script remotely
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Import_Artifacts.ps1"
$params = @{
  remoteDir = "`"$remoteUploadDir`""
  pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
  storageAccountName = "`"$storageAccountName`""
  storageContainerName = "`"$artifactsFolderNameConfig`""
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
Restart-AzVM -Name $config.dsg.dc.vmName -ResourceGroupName $config.dsg.dc.rg


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;