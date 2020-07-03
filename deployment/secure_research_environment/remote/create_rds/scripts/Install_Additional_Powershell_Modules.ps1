# Check installed modules
Write-Output "List installed modules..."
Get-Module

# Install module
Write-Output "Installing RDWebClientManagement..."
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name RDWebClientManagement -Force -AllowClobber -AcceptLicense
if ($?) {
    Write-Output " [o] Succeeded"
} else {
    Write-Output " [x] Failed!"
}

# Check installed modules
Write-Output "List installed modules..."
Get-Module
