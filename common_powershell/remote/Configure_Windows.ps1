# Set locale and timezone
# -----------------------
Write-Host "Setting locale and timezone...."
Set-WinHomeLocation -GeoId 0xf2
Set-TimeZone -Name "GMT Standard Time"
Set-WinSystemLocale en-GB
Set-Culture en-GB
Set-WinUserLanguageList -LanguageList en-GB -Force
Get-WinUserLanguageList
if ($?) {
    Write-Host " [o] Setting locale succeeded"
} else {
    Write-Host " [x] Setting locale failed!"
}


# Install Windows updates
# -----------------------
Write-Host "Installing Windows updates...."
Get-WindowsUpdate
$_ = Install-WindowsUpdate -AcceptAll -IgnoreReboot
if ($?) {
    Write-Host " [o] Installing Windows updates succeeded"
} else {
    Write-Host " [x] Installing Windows updates failed!"
}
