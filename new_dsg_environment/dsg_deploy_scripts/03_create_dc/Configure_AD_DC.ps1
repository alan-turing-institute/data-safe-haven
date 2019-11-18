param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/GenerateSasToken.psm1 -Force

# Get SRE config
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext

# Switch to SRE subscription
# --------------------------
$storageAccountSubscription = $config.dsg.subscriptionName
$_ = Set-AzContext -SubscriptionId $storageAccountSubscription;


# Remotely set the OS language for the DC
# ---------------------------------------
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Set_OS_Language.ps1"
Write-Host "Setting OS language for: $($config.dsg.dc.vmName)..."
$result = Invoke-AzVMRunCommand -Name $config.dsg.dc.vmName -ResourceGroupName $config.dsg.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;


# # Create users, groups and OUs
# Write-Output " - Creating users, groups and OUs"
# $cmd = (Join-Path $remoteDir "Create_Users_Groups_OUs.ps1")
# Invoke-Expression -Command "$cmd -dsgNetbiosName `"$dsgNetbiosName`" -dsgDn `"$dsgDn`" -dsgServerAdminSgName `"$dsgServerAdminSgName`" -dsgDcAdminUsername `"$dsgDcAdminUsername`""

# # Configure DNS
# Write-Output " - Configuring DNS"
# $cmd = (Join-Path $remoteDir "Configure_DNS.ps1")
# Invoke-Expression -Command "$cmd -subnetIdentityCidr `"$subnetIdentityCidr`" -subnetRdsCidr `"$subnetRdsCidr`" -subnetDataCidr `"$subnetDataCidr`" -shmFqdn `"$shmFqdn`" -shmDcIp `"$shmDcIp`""

# # Configure GPOs
# Write-Output " - Configuring GPOs"
# $cmd = (Join-Path $remoteDir "Configure_GPOs.ps1")
# $gpoBackupPath = (Join-Path $remoteDir "GPOs")
# Invoke-Expression -Command "$cmd -gpoBackupPath `"$gpoBackupPath`" -dsgNetbiosName `"$dsgNetbiosName`" -dsgDn `"$dsgDn`""

# # Copy Server Start Menu configuration
# Write-Output " - Copying server start menu"
# $sourceDir = Join-Path $remoteDir "ServerStartMenu"
# Copy-Item "$sourceDir" -Destination "F:\SYSVOL\domain\scripts" -Recurse




# # Upload artifacts to storage account
# #------------------------------------
# $storageAccountLocation = $config.dsg.location
# $storageAccountRg = $config.dsg.storage.artifacts.rg
# $storageAccountName = $config.dsg.storage.artifacts.accountName

# # Create storage account if it doesn't exist
# $_ = New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force
# $storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
# if($notExists) {
#   Write-Host " - Creating storage account '$storageAccountName'"
#   $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_GRS" -Kind "StorageV2"
# }
# $artifactsFolderName = "dc-config-scripts"
# $artifactsDir = (Join-Path $PSScriptRoot "artifacts" $artifactsFolderName "source")
# $containerName = $artifactsFolderName
# # Create container if it doesn't exist
# if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
#   Write-Host " - Creating container '$containerName' in storage account '$storageAccountName'"
#   $_ = New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
# }
# $blobs = @(Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context)
# $numBlobs = $blobs.Length
# if($numBlobs -gt 0){
#   Write-Host " - Deleting $numBlobs blobs aready in container '$containerName'"
#   $blobs | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $storageAccount.Context -Force}
#   while($numBlobs -gt 0){
#     Write-Host " - Waiting for deletion of $numBlobs remaining blobs"
#     Start-Sleep -Seconds 10
#     $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context).Length
#   }
# }

# $files = Get-ChildItem -File $artifactsDir -Recurse
# $numFiles = $files.Length
# Write-Host " - Uploading $numFiles files to container '$containerName'"
# $blobs = $files | Set-AzStorageBlobContent -Container $containerName -Context $storageAccount.Context
# $blobs = Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context
# $blobNames = $blobs | ForEach-Object{$_.Name}

# $sasToken = New-ReadOnlyAccountSasToken -subscriptionName $storageAccountSubscription `
#                 -resourceGroup $storageAccountRg -accountName $storageAccountName
# # Configure AD DC
# $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_AD_DC_Remote.ps1"

# $pipeSeparatedBlobNames = $blobNames -join "|"
# $params = @{
#   dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
#   dsgDn = "`"$($config.dsg.domain.dn)`""
#   dsgServerAdminSgName = "`"$($config.dsg.domain.securityGroups.serverAdmins.name)`""
#   dsgDcAdminUsername =  "`"$($config.dsg.dc.admin.username)`""
#   subnetIdentityCidr = "`"$($config.dsg.network.subnets.identity.cidr)`""
#   subnetRdsCidr = "`"$($config.dsg.network.subnets.rds.cidr)`""
#   subnetDataCidr = "`"$($config.dsg.network.subnets.data.cidr)`""
#   shmFqdn = "`"$($config.shm.domain.fqdn)`""
#   shmDcIp = "`"$($config.shm.dc.ip)`""
#   remoteDir = "`"C:\Scripts\$containerName`""
#   storageAccountName = "`"$storageAccountName`""
#   storageContainerName = "`"$containerName`""
#   sasToken = "`"$sasToken`""
#   pipeSeparatedBlobNames = "`"$pipeSeparatedBlobNames`""
# };

# $vmResourceGroup = $config.dsg.dc.rg
# $vmName = $config.dsg.dc.vmName;

# Write-Host " - Configuring AD DC"
# $result = Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup -Name "$vmName" `
#     -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
#     -Parameter $params

# Write-Output $result.Value;

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
