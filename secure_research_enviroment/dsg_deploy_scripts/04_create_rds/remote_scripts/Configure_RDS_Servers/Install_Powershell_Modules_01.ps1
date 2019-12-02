# Check installed modules
Write-Host "List installed modules..."
Get-Module

# Install PowerShellGet
Write-Host "Installing NuGet..."
Install-PackageProvider -Name NuGet -Force
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Install PowerShellGet
Write-Host "Installing PowerShellGet..."
Install-Module -Name PowerShellGet -Force -AllowClobber
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Check installed modules
Write-Host "List installed modules..."
Get-Module
