# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Position=0, HelpMessage = "Storage account name")]
    [string]$storageAccountName,
    [Parameter(Position=1, HelpMessage = "Storage service")]
    [string]$storageService,
    [Parameter(Position=2, HelpMessage = "File share or blob container name")]
    [string]$shareOrContainerName,
    [Parameter(Position=3, HelpMessage = "SAS token with read/list rights to the artifacts storage blob container")]
    [string]$sasToken,
    [Parameter(Position=4, HelpMessage = "Pipe separated list of remote file paths")]
    [string]$pipeSeparatedremoteFilePaths,
    [Parameter(Position=5, HelpMessage = "Absolute path to artifacts download directory")]
    [string]$downloadDir
)

Write-Host "storageAccountName $storageAccountName"
Write-Host "storageService $storageService"
Write-Host "shareOrContainerName $shareOrContainerName"
Write-Host "sasToken $sasToken"
Write-Host "pipeSeparatedremoteFilePaths $pipeSeparatedremoteFilePaths"
Write-Host "downloadDir $downloadDir"

# Deserialise blob names
$remoteFilePaths = $pipeSeparatedremoteFilePaths.Split("|")

# Clear any previously downloaded artifacts
Write-Output "Clearing all pre-existing files and folders from '$downloadDir'"
if(Test-Path -Path $downloadDir){
    Get-ChildItem $downloadDir -Recurse | Remove-Item -Recurse -Force
} else {
    $_ = New-Item -ItemType directory -Path $downloadDir
}

# Download artifacts
Write-Output "Downloading $numFiles files to '$downloadDir'"
foreach($remoteFilePath in $remoteFilePaths){
    $fileName = Split-Path -Leaf $remoteFilePath
    $fileDirRel = Split-Path -Parent $remoteFilePath
    $fileDirFull = Join-Path $downloadDir $fileDirRel
    if(-not (Test-Path -Path $fileDirFull )){
        $_ = New-Item -ItemType directory -Path $fileDirFull
    }
    $filePath = Join-Path $fileDirFull $fileName
    $remoteUrl = "https://$storageAccountName.$storageService.core.windows.net/$shareOrContainerName/$remoteFilePath";
    Write-Output " [ ] fetching $remoteUrl..."
    $_ = Invoke-WebRequest -Uri "$remoteUrl$sasToken" -OutFile $filePath;
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Failed!"
    }
}