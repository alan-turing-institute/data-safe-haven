# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Position = 0, HelpMessage = "Absolute path to remote artifacts directory")]
    [ValidateNotNullOrEmpty()]
    [string]$remoteDir,
    [Parameter(Position = 1, HelpMessage = "Names of blobs to dowload from artifacts storage blob container")]
    [ValidateNotNullOrEmpty()]
    [string]$pipeSeparatedBlobNames,
    [Parameter(Position = 2, HelpMessage = "Name of the artifacts storage account")]
    [ValidateNotNullOrEmpty()]
    [string]$storageAccountName,
    [Parameter(Position = 3, HelpMessage = "Name of the artifacts storage container")]
    [ValidateNotNullOrEmpty()]
    [string]$storageContainerName,
    [Parameter(Position = 4, HelpMessage = "SAS token with read/list rights to the artifacts storage blob container")]
    [ValidateNotNullOrEmpty()]
    [string]$sasToken
)

# Deserialise blob names
$blobNames = $pipeSeparatedBlobNames.Split("|")

# Clear any previously downloaded artifacts
Write-Output "Clearing all pre-existing files and folders from '$remoteDir'"
if (Test-Path -Path $remoteDir) {
    Get-ChildItem $remoteDir -Recurse | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType directory -Path $remoteDir
}

# Download artifacts
$numBlobs = $blobNames.length
Write-Output "Downloading $numBlobs files to '$remoteDir'..."
foreach ($blobName in $blobNames) {
    $fileName = Split-Path -Leaf $blobName
    $fileDirRel = Split-Path -Parent $blobName
    $fileDirFull = Join-Path $remoteDir $fileDirRel
    if (-not (Test-Path -Path $fileDirFull)) {
        $null = New-Item -ItemType Directory -Path $fileDirFull
    }
    $filePath = Join-Path $fileDirFull $fileName
    $blobUrl = "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$blobName$sasToken"
    $null = Invoke-WebRequest -Uri $blobUrl -OutFile $filePath
}

# Download AzureADConnect
Write-Output "Downloading AzureADConnect to '$remoteDir'..."
Invoke-WebRequest -Uri https://download.microsoft.com/download/B/0/0/B00291D0-5A83-4DE7-86F5-980BC00DE05A/AzureADConnect.msi -OutFile $remoteDir\AzureADConnect.msi;
if ($?) {
    Write-Output " [o] Completed"
} else {
    Write-Output " [x] Failed to download AzureADConnect"
}

# Extract GPOs
Write-Output "Extracting zip files..."
Expand-Archive $remoteDir\GPOs.zip -DestinationPath $remoteDir -Force
if ($?) {
    Write-Output " [o] Completed"
} else {
    Write-Output " [x] Failed to extract GPO zip files"
}

# List items
Write-Output "Contents of '$remoteDir' are:"
Write-Output (Get-ChildItem -Path $remoteDir)
