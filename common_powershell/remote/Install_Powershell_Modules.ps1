# Check installed modules
Write-Host "Currently installed modules..."
Get-Module
Write-Host "`n"


# Install NuGet
# -------------
$provider = "NuGet"
Write-Host "Installing $provider..."
Install-PackageProvider -Name $provider -Force 2>&1 | Out-Null
if (Get-PackageProvider -ListAvailable -Name $provider) {
    Write-Host " [o] $provider is installed"
} else {
    Write-Host " [x] Failed to install $provider!"
}


# Install modules
# ---------------
foreach ($module in ("PowerShellGet", "PSWindowsUpdate")) {
    Write-Host "Installing $module..."
    Install-Module -Name $module -Force -AllowClobber
    if (Get-Module -ListAvailable -Name $module) {
        Write-Host " [o] $module is installed"
    } else {
        Write-Host " [x] Failed to install $module!"
    }
}


# Check installed modules
# -----------------------
Write-Host "`nCurrently installed modules..."
Get-Module