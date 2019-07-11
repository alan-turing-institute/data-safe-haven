param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../../GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../../../../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../../../../GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

$dsgFqdn = $config.dsg.domain.fqdn
$dsgNetbiosName = $config.dsg.domain.netbiosName
$shmNetbiosName = $config.shm.domain.netbiosName
$dataSubnetIpPrefix = $config.dsg.network.subnets.data.prefix

$deployScript = @"
#Initialise the data drives
Stop-Service ShellHWDetection

`$CandidateRawDisks = Get-Disk |  Where {`$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach (`$RawDisk in `$CandidateRawDisks) {
    `$LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq `$RawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    `$Disk = Initialize-Disk -PartitionStyle GPT -Number `$RawDisk.Number
    `$Partition = New-Partition -DiskNumber `$RawDisk.Number -UseMaximumSize -AssignDriveLetter
    `$Volume = Format-Volume -Partition `$Partition -FileSystem NTFS -NewFileSystemLabel "DATA-`$LUN" -Confirm:`$false
}

Start-Service ShellHWDetection

# Create RDS Environment
Write-Output "Creating RDS Environment" 
New-RDSessionDeployment -ConnectionBroker "RDS.$dsgFqdn" -WebAccessServer "RDS.$dsgFqdn" -SessionHost @("RDSSH1.$dsgFqdn","RDSSH2.$dsgFqdn")
Add-RDServer -Server rds.$dsgFqdn -Role RDS-LICENSING -ConnectionBroker rds.$dsgFqdn
Set-RDLicenseConfiguration -LicenseServer rds.$dsgFqdn -Mode PerUser -ConnectionBroker rds.$dsgFqdn -Force
Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature
Add-RDServer -Server rds.$dsgFqdn -Role RDS-GATEWAY -ConnectionBroker rds.$dsgFqdn -GatewayExternalFqdn rds.$dsgFqdn

# Setup user profile disk shares
Write-Host -ForegroundColor Green "Creating user profile disk shares" 
Mkdir "F:\AppFileShares"
Mkdir "G:\RDPFileShares"
New-SmbShare -Path "F:\AppFileShares" -Name "AppFileShares" -FullAccess "$dsgNetbiosName\rds$","$dsgNetbiosName\rdssh1$","$dsgNetbiosName\domain admins"
New-SmbShare -Path "G:\RDPFileShares" -Name "RDPFileShares" -FullAccess "$dsgNetbiosName\rds$","$dsgNetbiosName\rdssh2$","$dsgNetbiosName\domain admins"

# Create collections
Write-Host -ForegroundColor Green "Creating Collections" 
New-RDSessionCollection -CollectionName "Remote Applications" -SessionHost rdssh1.$dsgFqdn -ConnectionBroker rds.$dsgFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Remote Applications" -UserGroup "$shmNetbiosName\SG $dsgNetbiosName Research Users" -ClientPrinterRedirected `$false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker rds.$dsgFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Remote Applications" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\rds\AppFileShares  -ConnectionBroker rds.$dsgFqdn

New-RDSessionCollection -CollectionName "Presentation Server" -SessionHost rdssh2.$dsgFqdn -ConnectionBroker rds.$dsgFqdn 
Set-RDSessionCollectionConfiguration -CollectionName "Presentation Server" -UserGroup "$shmNetbiosName\SG $dsgNetbiosName Research Users" -ClientPrinterRedirected `$false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker rds.$dsgFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Presentation Server" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\rds\RDPFileShares  -ConnectionBroker rds.$dsgFqdn

Write-Host -ForegroundColor Green "Creating Apps"
New-RDRemoteApp -Alias mstc -DisplayName "Custom VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn
New-RDRemoteApp -Alias putty -DisplayName "Custom VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn
New-RDRemoteApp -Alias WinSCP -DisplayName "File Transfer" -FilePath "C:\Program Files (x86)\WinSCP\WinSCP.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn
New-RDRemoteApp -Alias "chrome (1)" -DisplayName "Git Lab" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$dataSubnetIpPrefix.151" -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn 
New-RDRemoteApp -Alias 'chrome (2)' -DisplayName "HackMD" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$dataSubnetIpPrefix.152:3000" -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn 
New-RDRemoteApp -Alias "putty (1)" -DisplayName "Shared VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh $dataSubnetIpPrefix.160" -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn
New-RDRemoteApp -Alias 'mstc (2)' -DisplayName "Shared VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v $dataSubnetIpPrefix.160" -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn

# Install RDS webclient
Write-Output "Installing RDS webclient"
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name RDWebClientManagement -Force -AcceptLicense -AllowClobber
Install-RDWebClientPackage
Publish-RDWebClientPackage -Type Production -Latest
"@

$deployScriptLocalFilePath = (New-TemporaryFile).FullName
$deployScript | Out-File $deployScriptLocalFilePath
$deployScriptName = "Deploy_RDS_Environment.ps1"

# Temporarily switch to storage subscription
$prevContext = Get-AzContext
$storageAccountSubscription = $config.dsg.subscriptionName;
$_ = Set-AzContext -SubscriptionId $storageAccountSubscription;

# Upload script to storage account
$storageAccountLocation = $config.dsg.location
$storageAccountRg = $config.dsg.storage.artifacts.rg
$storageAccountName = $config.dsg.storage.artifacts.accountName

# Create storage account if it doesn't exist
$_ = New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force;
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
if($notExists) {
  Write-Host " - Creating storage account '$storageAccountName'"
  $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_GRS" -Kind "StorageV2"
}
$containerName =  "rds-config-scripts"
# Create container if it doesn't exist
if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
  Write-Host " - Creating container '$containerName' in storage account '$storageAccountName'"
  $_ = New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
}
$blobs = @(Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context)
$numBlobs = $blobs.Length
if($numBlobs -gt 0){
  Write-Host " - Deleting $numBlobs blobs aready in container '$containerName'"
  $blobs | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $storageAccount.Context -Force}
  while($numBlobs -gt 0){
    Write-Host " - Waiting for deletion of $numBlobs remaining blobs"
    Start-Sleep -Seconds 10
    $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context).Length
  }
}

# Upload script
Write-Host " - Uploading '$deployScriptName to container '$containerName'"
$_ = Set-AzStorageBlobContent -File $deployScriptLocalFilePath -Blob $deployScriptName -Container $containerName -Context $storageAccount.Context;

# Get SAS token
$sasToken = New-ReadOnlyAccountSasToken -subscriptionName $storageAccountSubscription `
-resourceGroup $storageAccountRg -accountName $storageAccountName

$remoteFilePath = $deployScriptName;

# $pipeSeparatedFilePaths = $filePaths -join "|"
$pipeSeparatedFilePaths = $remoteFilePath # A single value here is fine.

# Temporarily switch to DSG subscription to run remote scripts
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName

# Download software packages to RDS Session Hosts
$packageDownloadParams = @{
    storageAccountName = "`"$storageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerName`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$pipeSeparatedFilePaths`""
    downloadDir = "C:\Scripts"
}

$scriptPath = Join-Path $PSScriptRoot ".." "remote_scripts" "Download_Files.ps1"
Write-Host " - Copying script(s) to RDS gateway"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.rds.rg `
    -Name "$($config.dsg.rds.gateway.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $packageDownloadParams

Write-Output $result.Value[0]
Write-Output $result.Value[1]

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;