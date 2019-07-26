# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(Position=0, HelpMessage = "DSG Netbios name")]
  [string]$dsgNetbiosName,
  [Parameter(Position=1, HelpMessage = "DSG DN")]
  [string]$dsgDn,
  [Parameter(Position=2, HelpMessage = "DSG Server admin security group name")]
  [string]$dsgServerAdminSgName,
  [Parameter(Position=3, HelpMessage = "DSG DC admin username")]
  [string]$dsgDcAdminUsername,
  [Parameter(Position=4, HelpMessage = "DSG Identity subnet CIDR")]
  [string]$subnetIdentityCidr,
  [Parameter(Position=5, HelpMessage = "DSG RDS subnet CIDR")]
  [string]$subnetRdsCidr,
  [Parameter(Position=6, HelpMessage = "DSG Data subnet CIDR")]
  [string]$subnetDataCidr,
  [Parameter(Position=7, HelpMessage = "SHM FQDN")]
  [string]$shmFqdn,
  [Parameter(Position=8, HelpMessage = "SHM DC IP")]
  [string]$shmDcIp,
  [Parameter(Position=9, HelpMessage = "Absolute path to remote artifacts directory")]
  [string]$remoteDir,
  [Parameter(Position=10, HelpMessage = "Name of the artifacts storage account")]
  [string]$storageAccountName,
  [Parameter(Position=11, HelpMessage = "Name of the artifacts storage container")]
  [string]$storageContainerName,
  [Parameter(Position=12, HelpMessage = "SAS token with read/list rights to the artifacts storage blob container")]
  [string]$sasToken,
  [Parameter(Position=13, HelpMessage = "Names of blobs to dowload from artifacts storage blob container")]
  [string]$pipeSeparatedBlobNames
)
# Deserialise blob names
$blobNames = $pipeSeparatedBlobNames.Split("|")

# Clear any previously downloaded artifacts
Write-Output " - Clearing all pre-existing files and folders from '$remoteDir'"
if(Test-Path -Path $remoteDir){
  Get-ChildItem $remoteDir -Recurse | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType directory -Path $remoteDir
}

# Download artifacts
Write-Output " - Downloading $numFiles files to '$remoteDir'"
foreach($blobName in $blobNames){
  $fileName = Split-Path -Leaf $blobName
  $fileDirRel = Split-Path -Parent $blobName
  $fileDirFull = Join-Path $remoteDir $fileDirRel
  if(-not (Test-Path -Path $fileDirFull )){
    $_ = New-Item -ItemType directory -Path $fileDirFull
  }
  $filePath = Join-Path $fileDirFull $fileName 
  $blobUrl = "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$blobName$sasToken";
  $_ = Invoke-WebRequest -Uri $blobUrl -OutFile $filePath;
}

# Set OS locale
Write-Output " - Setting OS locale"
$cmd = (Join-Path $remoteDir "Set_OS_Locale.ps1")
Invoke-Expression -Command "$cmd"

# Create users, groups and OUs
Write-Output " - Creating users, groups and OUs"
$cmd = (Join-Path $remoteDir "Create_Users_Groups_OUs.ps1")
Invoke-Expression -Command "$cmd -dsgNetbiosName `"$dsgNetbiosName`" -dsgDn `"$dsgDn`" -dsgServerAdminSgName `"$dsgServerAdminSgName`" -dsgDcAdminUsername `"$dsgDcAdminUsername`""

# Configure DNS
Write-Output " - Configuring DNS"
$cmd = (Join-Path $remoteDir "Configure_DNS.ps1")
Invoke-Expression -Command "$cmd -subnetIdentityCidr `"$subnetIdentityCidr`" -subnetRdsCidr `"$subnetRdsCidr`" -subnetDataCidr `"$subnetDataCidr`" -shmFqdn `"$shmFqdn`" -shmDcIp `"$shmDcIp`""

# Configure GPOs
Write-Output " - Configuring GPOs"
$cmd = (Join-Path $remoteDir "Configure_GPOs.ps1")
$gpoBackupPath = (Join-Path $remoteDir "GPOs")
Invoke-Expression -Command "$cmd -gpoBackupPath `"$gpoBackupPath`" -dsgNetbiosName `"$dsgNetbiosName`" -dsgDn `"$dsgDn`""

# Copy Server Start Menu configuration
Write-Output " - Copying server start menu"
$sourceDir = Join-Path $remoteDir "ServerStartMenu"
Copy-Item "$sourceDir" -Destination "F:\SYSVOL\domain\scripts" -Recurse