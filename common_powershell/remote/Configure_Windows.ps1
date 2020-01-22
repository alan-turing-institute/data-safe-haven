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
    Write-Host " [o] Completed"
} else {
    Write-Host " [x] Failed"
}


# Install Windows updates
# -----------------------
Get-WindowsUpdate
Install-WindowsUpdate -AcceptAll -IgnoreReboot
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}
