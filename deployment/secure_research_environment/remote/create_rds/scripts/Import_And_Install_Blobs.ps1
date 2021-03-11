# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Base-64 encoded array of blob names to download from storage blob container")]
    [string]$blobNameArrayB64,
    [Parameter(HelpMessage = "Absolute path to directory which blobs should be downloaded to")]
    [string]$downloadDir,
    [Parameter(HelpMessage = "Base-64 encoded SAS token with read/list rights to the storage blob container")]
    [string]$sasTokenB64,
    [Parameter(HelpMessage = "File share or blob container name")]
    [string]$shareOrContainerName,
    [Parameter(HelpMessage = "Storage account name")]
    [string]$storageAccountName,
    [Parameter(HelpMessage = "Storage service")]
    [string]$storageService
)

# Deserialise Base-64 encoded variables
# -------------------------------------
$blobNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($blobNameArrayB64)) | ConvertFrom-Json
$sasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($sasTokenB64))


# Clear any previously downloaded artifacts
# -----------------------------------------
Write-Output "Clearing all pre-existing files and folders from '$downloadDir'"
if (Test-Path -Path $downloadDir) {
    Get-ChildItem $downloadDir -Recurse | Remove-Item -Recurse -Force
} else {
    $null = New-Item -ItemType directory -Path $downloadDir
}

# Download artifacts
Write-Output "Downloading $($blobNames.Count) files to '$downloadDir'"
foreach ($blobName in $blobNames) {
    # Ensure that local directory exists
    $localDir = Join-Path $downloadDir $(Split-Path -Parent $blobName)
    if (-Not (Test-Path -Path $localDir)) {
        $null = New-Item -ItemType directory -Path $localDir
    }
    $fileName = Split-Path -Leaf $blobName
    $localFilePath = Join-Path $localDir $fileName

    # Download file from blob storage
    $blobUrl = "https://${storageAccountName}.${storageService}.core.windows.net/${shareOrContainerName}/${blobName}"
    Write-Output " [ ] Fetching $blobUrl..."
    $null = Invoke-WebRequest -Uri "${blobUrl}${sasToken}" -OutFile $localFilePath
    if ($?) {
        Write-Output " [o] Succeeded"
    } else {
        Write-Output " [x] Failed!"
    }

    # If this file is an msi/exe then install it
    if ((Test-Path -Path $localFilePath) -And ($fileName -Match ".*\.(msi|exe)\b")) {
        if ($fileName -like "*.msi") {
            Write-Output " [ ] Installing $fileName..."
            Start-Process $localFilePath -ArgumentList '/quiet' -Verbose -Wait
        } elseif ($fileName -like "*WinSCP*exe") {
            Write-Output " [ ] Installing $fileName..."
            Start-Process $localFilePath -ArgumentList '/SILENT', '/ALLUSERS' -Verbose -Wait
        } else {
            continue
        }
        if ($?) {
            Write-Output " [o] Succeeded"
        } else {
            Write-Output " [x] Failed!"
        }
    }
}
