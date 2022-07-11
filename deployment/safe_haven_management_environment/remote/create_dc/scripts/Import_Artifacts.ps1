# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Base-64 encoded array of blob names to download from storage blob container")]
    [ValidateNotNullOrEmpty()]
    [string]$blobNameArrayB64,
    [Parameter(HelpMessage = "Absolute path to directory which blobs should be downloaded to")]
    [ValidateNotNullOrEmpty()]
    [string]$targetDirectory,
    [Parameter(HelpMessage = "Base-64 encoded SAS token with read/list rights to the storage blob container")]
    [ValidateNotNullOrEmpty()]
    [string]$sasTokenB64,
    [Parameter(HelpMessage = "Name of the storage account")]
    [ValidateNotNullOrEmpty()]
    [string]$storageAccountName,
    [Parameter(HelpMessage = "Name of the storage container")]
    [ValidateNotNullOrEmpty()]
    [string]$storageContainerName
)

# Deserialise Base-64 encoded variables
# -------------------------------------
$blobNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($blobNameArrayB64)) | ConvertFrom-Json
$sasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($sasTokenB64))


# Clear any previously downloaded artifacts
# -----------------------------------------
Write-Output "Clearing all pre-existing files and folders from '$targetDirectory'"
if (Test-Path -Path $targetDirectory) {
    Get-ChildItem $targetDirectory -Recurse | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType directory -Path $targetDirectory
}


# Download artifacts
# ------------------
Write-Output "Downloading $($blobNames.Length) files to '$targetDirectory'..."
foreach ($blobName in $blobNames) {
    # Ensure that local directory exists
    $localDir = Join-Path $targetDirectory $(Split-Path -Parent $blobName)
    if (-not (Test-Path -Path $localDir)) {
        $null = New-Item -ItemType Directory -Path $localDir
    }
    $fileName = Split-Path -Leaf $blobName
    $localFilePath = Join-Path $localDir $fileName

    # Download file from blob storage
    $blobUrl = "https://${storageAccountName}.blob.core.windows.net/${storageContainerName}/${blobName}${sasToken}"
    Write-Output " [ ] Fetching $blobUrl..."
    $null = Invoke-WebRequest -Uri $blobUrl -OutFile $localFilePath
    if ($?) {
        Write-Output " [o] Succeeded"
    } else {
        Write-Output " [x] Failed!"
    }
}


# Extract GPOs
# ------------
Write-Output "Extracting zip files..."
Expand-Archive "${targetDirectory}\GPOs.zip" -DestinationPath $targetDirectory -Force
if ($?) {
    Write-Output " [o] Completed"
} else {
    Write-Output " [x] Failed to extract GPO zip files"
}


# List items
# ----------
Write-Output "Contents of '$targetDirectory' are:"
Write-Output (Get-ChildItem -Path $targetDirectory)
