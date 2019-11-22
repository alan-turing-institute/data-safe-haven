# Install module
Write-Host "Installing modules..."
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name RDWebClientManagement -Force -AllowClobber -AcceptLicense
if ($?) {
    Write-Host " [o] Module installation succeeded"
} else {
    Write-Host " [x] Module installation failed!"
}

# Install RDS webclient
Write-Host "Installing RDS webclient..."
Install-RDWebClientPackage
if ($?) {
    Write-Host " [o] RDS webclient installation succeeded"
} else {
    Write-Host " [x] RDS webclient installation failed!"
}