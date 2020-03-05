# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(Position=0, HelpMessage = "Absolute path to remote artifacts directory")]
  [ValidateNotNullOrEmpty()]
  [string]$remoteDir,
  [Parameter(Position=1, HelpMessage = "Names of blobs to dowload from artifacts storage blob container")]
  [ValidateNotNullOrEmpty()]
  [string]$pipeSeparatedBlobNames,
  [Parameter(Position=2, HelpMessage = "Name of the artifacts storage account")]
  [ValidateNotNullOrEmpty()]
  [string]$storageAccountName,
  [Parameter(Position=3, HelpMessage = "Name of the artifacts storage container")]
  [ValidateNotNullOrEmpty()]
  [string]$storageContainerName,
  [Parameter(Position=4, HelpMessage = "SAS token with read/list rights to the artifacts storage blob container")]
  [ValidateNotNullOrEmpty()]
  [string]$sasToken
)

# Deserialise blob names
$blobNames = $pipeSeparatedBlobNames.Split("|")

# Clear any previously downloaded artifacts
Write-Host "Clearing all pre-existing files and folders from '$remoteDir'"
if(Test-Path -Path $remoteDir){
  Get-ChildItem $remoteDir -Recurse | Remove-Item -Recurse -Force
} else {
  New-Item -ItemType directory -Path $remoteDir
}

# Download artifacts
$numBlobs = $blobNames.Length
Write-Host "Downloading $numBlobs files to '$remoteDir'..."
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

# Copy server start menu layout
Write-Host "Copying server start menu layout..."
$sourceFile = Join-Path $remoteDir "StartMenuLayoutModification.xml"
$targetDir = "F:\SYSVOL\domain\scripts\ServerStartMenu"
if(-not $(Test-Path -Path $targetDir)) {
  New-Item -ItemType directory -Path $targetDir
}
$_ = Copy-Item "$sourceFile" -Destination $(Join-Path $targetDir "LayoutModification.xml")
if ($?) {
  Write-Host " [o] Succeeded in copying start menu layout"
} else {
  Write-Host " [x] Failed to copy start menu layout"
}


# Extract GPOs
Write-Host "Extracting zip files..."
Expand-Archive $remoteDir\GPOs.zip -DestinationPath $remoteDir -Force
if ($?) {
  Write-Host " [o] Succeeded in extracting GPO zip files"
} else {
  Write-Host " [x] Failed to extract GPO zip files"
}

# List items
Write-Host "Contents of '$remoteDir' are:"
Write-Host (Get-ChildItem -Path $remoteDir)
