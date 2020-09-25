# Variables
$TimeZone = "GMT Standard Time"
$NTPServer = "ntp.kopicloud.local"

# Set locale
# -----------------------

Write-Output "Setting locale and timezone..."
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

# Configure NTP and restart service
Set-TimeZone -Name $TimeZone
$success = $?
$success = $success -and $?
Push-Location
Set-Location HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers
$success = $success -and $?
Set-ItemProperty . 0 $NTPServer
$success = $success -and $?
Set-ItemProperty . "(Default)" "0"
$success = $success -and $?
Set-Location HKLM:\SYSTEM\CurrentControlSet\services\W32Time\Parameters
$success = $success -and $?
Set-ItemProperty . NtpServer $NTPServer
$success = $success -and $?
Pop-Location
Stop-Service w32time
$success = $success -and $?
Start-Service w32time
$success = $success -and $?

if ($success) {
    Write-Output " [o] Setting timezone & ntp server succeeded"
} else {
    Write-Output " [x] Setting timezone & ntp server failed!"
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
