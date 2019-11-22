# Install module
Write-Host -ForegroundColor Cyan "Installing RDWebClientManagement module..."
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name RDWebClientManagement -Force -AllowClobber -AcceptLicense
if ($?) {
    Write-Host " [o] Module installation succeeded"
} else {
    Write-Host " [x] Module installation failed!"
}

# Install RDS webclient
Write-Host -ForegroundColor Cyan "Installing RDS webclient..."
Install-RDWebClientPackage
if ($?) {
    Write-Host " [o] RDS webclient installation succeeded"
} else {
    Write-Host " [x] RDS webclient installation failed!"
}