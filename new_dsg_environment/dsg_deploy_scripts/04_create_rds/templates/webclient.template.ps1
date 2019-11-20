# Install RDS webclient
Write-Output "Installing RDS webclient"
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name RDWebClientManagement -Force -AllowClobber -AcceptLicense
Install-RDWebClientPackage