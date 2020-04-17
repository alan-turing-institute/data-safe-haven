# Set locale and timezone
# -----------------------
Write-Host "Setting locale and timezone..."
Set-WinHomeLocation -GeoId 0xf2
$success = $?
Set-TimeZone -Name "GMT Standard Time"
$success = $success -and $?
Set-WinSystemLocale en-GB
$success = $success -and $?
Set-Culture en-GB
$success = $success -and $?
Set-WinUserLanguageList -LanguageList en-GB -Force
$success = $success -and $?
Get-WinUserLanguageList
if ($success) {
    Write-Host " [o] Setting locale succeeded"
} else {
    Write-Host " [x] Setting locale failed!"
}


# Install Windows updates
# -----------------------
$existingUpdateTitles = Get-WUHistory | Where-Object { ($_.Result -eq "Succeeded") } | ForEach-Object { $_.Title }
$updatesToInstall = Get-WindowsUpdate -MicrosoftUpdate
Write-Host "`nInstalling $($updatesToInstall.Count) Windows updates:"
foreach ($update in $updatesToInstall) {
    Write-Host " ... $($update.Title)"
}
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot 2>&1 | Out-Null
if ($?) {
    Write-Host " [o] Installing Windows updates succeeded."
} else {
    Write-Host " [x] Installing Windows updates failed!"
}


# Report any updates that were installed
# --------------------------------------
Write-Host "`nNewly installed Windows updates:"
$installedUpdates = Get-WUHistory | Where-Object { ($_.Result -eq "Succeeded") -And ($_.Title -NotIn $existingUpdateTitles) }
foreach ($update in $installedUpdates) {
    Write-Host " ... $($update.Title)"
}
