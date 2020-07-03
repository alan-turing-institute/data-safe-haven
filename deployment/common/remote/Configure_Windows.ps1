# Set locale and timezone
# -----------------------
Write-Output "Setting locale and timezone..."
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
    Write-Output " [o] Setting locale succeeded"
} else {
    Write-Output " [x] Setting locale failed!"
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
