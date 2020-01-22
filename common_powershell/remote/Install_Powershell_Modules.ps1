# Check installed modules
Write-Host "Currently installed modules..."
Get-Module

# Install NuGet
Write-Host "Installing NuGet..."
Install-PackageProvider -Name NuGet -Force
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Install PowerShellGet
Write-Host "Installing PSWindowsUpdate..."
Install-Module -Name PSWindowsUpdate -Force -AllowClobber
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
Write-Host "Currently installed modules..."
Get-Module