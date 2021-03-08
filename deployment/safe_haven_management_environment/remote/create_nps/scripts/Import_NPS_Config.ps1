# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Base-64 encoded array of blob names to download from artifacts storage blob container")]
    [ValidateNotNullOrEmpty()]
    [string]$blobNameArrayB64,
    [Parameter(HelpMessage = "Absolute path to directory which artifacts should be downloaded to")]
    [ValidateNotNullOrEmpty()]
    [string]$installationDir,
    [Parameter(HelpMessage = "Base-64 encoded SAS token with read/list rights to the artifacts storage blob container")]
    [ValidateNotNullOrEmpty()]
    [string]$sasTokenB64,
    [Parameter(HelpMessage = "Name of the artifacts storage account")]
    [ValidateNotNullOrEmpty()]
    [string]$storageAccountName,
    [Parameter(HelpMessage = "Name of the artifacts storage container")]
    [ValidateNotNullOrEmpty()]
    [string]$storageContainerName
)


# Deserialise Base-64 encoded variables
# -------------------------------------
$blobNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($blobNameArrayB64)) | ConvertFrom-Json
$sasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($sasTokenB64))


# Download artifacts from blob storage
# ------------------------------------
$numBlobs = $blobNames.length
Write-Output "Downloading $numBlobs files to '$installationDir'..."
foreach ($blobName in $blobNames) {
    $fileName = Split-Path -Leaf $blobName
    $fileDirectory = Join-Path $installationDir $(Split-Path -Parent $blobName)
    if (-not (Test-Path -Path $fileDirectory)) {
        $null = New-Item -ItemType directory -Path $fileDirectory
    }
    $filePath = Join-Path $fileDirectory $fileName
    $blobUrl = "https://${storageAccountName}.blob.core.windows.net/${storageContainerName}/${blobName}${sasToken}"
    $null = Invoke-WebRequest -Uri $blobUrl -OutFile $filePath
}


# Import the NPS configuration
# ----------------------------
Write-Output "Importing NPS configuration for RDG_CAP policy..."
Import-NpsConfiguration -Path (Join-Path $installationDir "nps_config.xml")
