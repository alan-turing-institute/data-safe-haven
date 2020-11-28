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
# ----------------------
$blobNames = $pipeSeparatedBlobNames.Split("|")


# Download artifacts from blob storage
# ------------------------------------
$numBlobs = $blobNames.length
Write-Output "Downloading $numBlobs files to '$remoteDir'..."
foreach ($blobName in $blobNames) {
    $fileName = Split-Path -Leaf $blobName
    $fileDirRel = Split-Path -Parent $blobName
    $fileDirFull = Join-Path $remoteDir $fileDirRel
    if (-not (Test-Path -Path $fileDirFull)) {
        $null = New-Item -ItemType directory -Path $fileDirFull
    }
    $filePath = Join-Path $fileDirFull $fileName
    $blobUrl = "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$blobName$sasToken"
    $null = Invoke-WebRequest -Uri $blobUrl -OutFile $filePath
}


# Import the NPS configuration
# ----------------------------
Write-Output "Importing NPS configuration for RDG_CAP policy..."
Import-NpsConfiguration -Path (Join-Path $remoteDir "nps_config.xml")
