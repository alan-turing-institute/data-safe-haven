# Install module
Write-Host -ForegroundColor Cyan "Installing modules..."
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name RDWebClientManagement -Force -AllowClobber -AcceptLicense

# Install RDS webclient
Write-Host -ForegroundColor Cyan "Installing RDS webclient..."
Install-RDWebClientPackage