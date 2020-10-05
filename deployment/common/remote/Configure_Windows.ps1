# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $false, HelpMessage = "Time zone to use")]
    [string]$TimeZone = "",
    [Parameter(Mandatory = $false, HelpMessage = "NTP server to use")]
    [string]$NTPServer = ""
)


# Set locale
# ----------
Write-Output "Setting locale..."
Set-WinHomeLocation -GeoId 0xf2
$success = $?
Set-WinSystemLocale en-GB
$success = $success -and $?
Set-Culture en-GB
$success = $success -and $?
Set-WinUserLanguageList -LanguageList en-GB -Force
$success = $success -and $?
Get-WinUserLanguageList
if ($success) {
    Write-Output " [o] Setting locale succeeded"
} else {
    Write-Output " [x] Setting locale failed!"
}


# Configure Time Zone and NTP server
# ----------------------------------
if (-not ($TimeZone -and $NTPServer)) {
    Write-Output "Setting timezone and NTP server..."
    Set-TimeZone -Name $TimeZone
    $success = $?
    Push-Location
    Set-Location HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers
    $success = $success -and $?
    Remove-ItemProperty . -Name "*"
    $success = $success -and $?
    Set-ItemProperty . 0 $NTPServer
    $success = $success -and $?
    Set-ItemProperty . "(Default)" "0"
    $success = $success -and $?
    # Check that there are exactly two registry strings
    $success = $success -and (((Get-ItemProperty .).PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" -and $_.Name -notlike "PS*" } | Measure-Object | Select-Object Count).Count -eq 2)
    Set-Location HKLM:\SYSTEM\CurrentControlSet\services\W32Time\Parameters
    $success = $success -and $?
    Set-ItemProperty . NtpServer $NTPServer
    $success = $success -and $?
    Pop-Location
    Stop-Service W32Time
    $success = $success -and $?
    Start-Service W32Time
    $success = $success -and $?
    if ($success) {
        Write-Output " [o] Setting time zone and NTP server succeeded"
    } else {
        Write-Output " [x] Setting time zone and NTP server failed!"
    }
} else {
    Write-Output " [x] Invalid time zone '$TimeZone' and/or NTP server '$NTPServer' provided!"
}



# Install Windows updates
# -----------------------
$existingUpdateTitles = Get-WUHistory | Where-Object { ($_.Result -eq "Succeeded") } | ForEach-Object { $_.Title }
$updatesToInstall = Get-WindowsUpdate -MicrosoftUpdate
Write-Output "`nInstalling $($updatesToInstall.Count) Windows updates:"
foreach ($update in $updatesToInstall) {
    Write-Output " ... $($update.Title)"
}
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot 2>&1 | Out-Null
if ($?) {
    Write-Output " [o] Installing Windows updates succeeded."
} else {
    Write-Output " [x] Installing Windows updates failed!"
}


# Report any updates that were installed
# --------------------------------------
Write-Output "`nNewly installed Windows updates:"
$installedUpdates = Get-WUHistory | Where-Object { ($_.Result -eq "Succeeded") -And ($_.Title -NotIn $existingUpdateTitles) }
foreach ($update in $installedUpdates) {
    Write-Output " ... $($update.Title)"
}
