# Check installed modules
Write-Host "List installed modules..."
Get-Module

# Install module
Write-Host "Installing RDWebClientManagement..."
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name RDWebClientManagement -Force -AllowClobber -AcceptLicense
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Check installed modules
Write-Host "List installed modules..."
Get-Module
