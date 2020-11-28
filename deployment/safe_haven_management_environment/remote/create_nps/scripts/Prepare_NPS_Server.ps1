# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Position = 0, HelpMessage = "Absolute path to remote artifacts directory")]
    [ValidateNotNullOrEmpty()]
    [string]$remoteDir
)


# Clear any previously downloaded artifacts
# -----------------------------------------
Write-Output "Clearing all pre-existing files and folders from '$remoteDir'"
if (Test-Path -Path $remoteDir) {
    $null = Get-ChildItem $remoteDir -Recurse | Remove-Item -Recurse -Force
} else {
    $null = New-Item -ItemType directory -Path $remoteDir
}


# Install NPAS
# ------------
Write-Output "Installing NPAS feature..."
Install-WindowsFeature NPAS -IncludeManagementTools
if ($?) {
    Write-Output " [o] Successfully installed NPAS"
} else {
    Write-Output " [x] Failed to install NPAS"
}


# Set SQL Firewall rules
# ----------------------
Write-Output "Setting SQL Firewall rules..."
$null = New-NetFirewallRule -DisplayName "SQL" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1433 -Profile Domain -Enabled True
if ($?) {
    Write-Output " [o] Set inbound rule"
} else {
    Write-Output " [x] Failed to set inbound rule"
}
$null = New-NetFirewallRule -DisplayName "SQL" -Direction Outbound -Action Allow -Protocol TCP -LocalPort 1433 -Profile Domain -Enabled True
if ($?) {
    Write-Output " [o] Set outbound rule"
} else {
    Write-Output " [x] Failed to set outbound rule"
}


# Format the data drives
# ----------------------
Write-Output "Formatting data drive..."
Stop-Service ShellHWDetection
$CandidateRawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'raw' } | Sort -Property Number
foreach ($RawDisk in $CandidateRawDisks) {
    $null = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
    $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
    $null = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "SQLDATA" -Confirm:$false
}
Start-Service ShellHWDetection
if ($?) {
    Write-Output " [o] Completed"
} else {
    Write-Output " [x] Failed to set outbound rule"
}


# Download and install the NPS Extension
# --------------------------------------
Write-Output "Downloading NPS extension to '$remoteDir'..."
$npsExtnPath = Join-Path $remoteDir "NpsExtnForAzureMfaInstaller.exe"
Invoke-WebRequest -Uri https://download.microsoft.com/download/B/F/F/BFFB4F12-9C09-4DBC-A4AF-08E51875EEA9/NpsExtnForAzureMfaInstaller.exe -OutFile $npsExtnPath
if ($?) {
    Write-Output " [o] Successfully downloaded NPS extension"
} else {
    Write-Output " [x] Failed to download NPS extension"
}
Write-Output "Installing NPS extension..."
Start-Process $npsExtnPath -ArgumentList '/install', '/quiet'
if ($?) {
    Write-Output " [o] Successfully installed NPS extension"
} else {
    Write-Output " [x] Failed to install NPS extension"
}
