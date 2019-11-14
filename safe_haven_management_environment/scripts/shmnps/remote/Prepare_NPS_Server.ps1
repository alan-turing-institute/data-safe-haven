# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(Position=0, HelpMessage = "Absolute path to remote artifacts directory")]
  [ValidateNotNullOrEmpty()]
  [string]$remoteDir
)

# Clear any previously downloaded artifacts
Write-Host "Clearing all pre-existing files and folders from '$remoteDir'"
if(Test-Path -Path $remoteDir){
  Get-ChildItem $remoteDir -Recurse | Remove-Item -Recurse -Force
} else {
  New-Item -ItemType directory -Path $remoteDir
}

# Set locale and timezone
# -----------------------
Write-Host "Setting locale and timezone...."
Set-WinHomeLocation -GeoId 0xf2
Set-TimeZone -Name "GMT Standard Time"
Set-WinSystemLocale en-GB
Set-Culture en-GB
Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList -Language en-GB) -Force
if ($?) {
  Write-Host " [o] Completed"
} else {
  Write-Host " [x] Failed"
}

# Install NPAS
# ------------
Write-Host "Installing NPAS feature..."
Install-WindowsFeature NPAS -IncludeManagementTools
if ($?) {
  Write-Host " [o] Completed"
} else {
  Write-Host " [x] Failed"
}

# Set SQL Firewall rules
# ----------------------
Write-Host "Setting SQL Firewall rules..."
New-NetFirewallRule -DisplayName "SQL" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1433 -Profile Domain -Enabled True
if ($?) {
  Write-Host " [o] Set inbound rule"
} else {
  Write-Host " [x] Failed to set inbound rule"
}
New-NetFirewallRule -DisplayName "SQL" -Direction Outbound -Action Allow -Protocol TCP -LocalPort 1433 -Profile Domain -Enabled True
if ($?) {
  Write-Host " [o] Set outbound rule"
} else {
  Write-Host " [x] Failed to set outbound rule"
}

# Format the data drives
# ----------------------
Write-Host "Formatting data drive..."
Stop-Service ShellHWDetection
$CandidateRawDisks = Get-Disk |  Where {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach ($RawDisk in $CandidateRawDisks) {
  $LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq $RawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
  $Disk = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
  $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
  $Volume = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "SQLDATA" -Confirm:$false
}
Start-Service ShellHWDetection
if ($?) {
  Write-Host " [o] Completed"
} else {
  Write-Host " [x] Failed to set outbound rule"
}


# Download the NPS Extension
# --------------------------
Write-Host "Downloading NPS Extension to '$remoteDir'..."
Invoke-WebRequest -Uri https://download.microsoft.com/download/B/F/F/BFFB4F12-9C09-4DBC-A4AF-08E51875EEA9/NpsExtnForAzureMfaInstaller.exe -OutFile $remoteDir\NpsExtnForAzureMfaInstaller.exe;
if ($?) {
  Write-Host " [o] Completed"
} else {
  Write-Host " [x] Failed to download NPS extension"
}

