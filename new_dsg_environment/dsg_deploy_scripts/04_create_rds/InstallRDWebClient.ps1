Install-Module -Name PowerShellGet -Force

# Restart PowerShell

Install-Module -Name RDWebClientManagement
Install-RDWebClientPackage
Import-RDWebClientBrokerCert #Enter path to certificate here
Publish-RDWebClientPackage -Type Production -Latest