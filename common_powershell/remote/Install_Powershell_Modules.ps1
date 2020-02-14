# Check installed modules
Write-Host "Currently installed modules..."
Get-Module
Write-Host "`n"


# Install NuGet
# -------------
Write-Host "Installing NuGet..."
Install-PackageProvider -Name NuGet -Force 2>&1 | Out-Null
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}


# Install modules
# ---------------
foreach ($module in ("PowerShellGet", "PSWindowsUpdate")) {
    Write-Host "Installing $module..."
    Install-Module -Name $module -Force -AllowClobber
    if ($?) {
        Write-Host " [o] Succeeded"
    } else {
        Write-Host " [x] Failed!"
    }
}


# Check installed modules
# -----------------------
Write-Host "`nCurrently installed modules..."
Get-Module