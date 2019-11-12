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
Write-Host -ForegroundColor Cyan "Clearing all pre-existing files and folders from '$remoteDir'"
if(Test-Path -Path $remoteDir){
  Get-ChildItem $remoteDir -Recurse | Remove-Item -Recurse -Force
} else {
  New-Item -ItemType directory -Path $remoteDir
}

# Download artifacts
$numBlobs = $blobNames.Length
Write-Host -ForegroundColor Cyan "Downloading $numBlobs files to '$remoteDir'"
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

# Extract GPOs and list items
Write-Host -ForegroundColor Cyan "Extracting zip files..."
Expand-Archive C:\Scripts\GPOs.zip -DestinationPath C:\Scripts\ -Force
Write-Host (Get-ChildItem -Path C:\Scripts\)
