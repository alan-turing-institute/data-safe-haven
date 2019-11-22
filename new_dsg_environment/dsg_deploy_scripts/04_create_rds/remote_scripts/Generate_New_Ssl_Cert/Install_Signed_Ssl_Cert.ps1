# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  [Parameter(Position=0, HelpMessage = "Full chain for SSL certificate, including CA intermediate signing certificate, in ASCII *.pem format")]
  [string]$certFullChain,
  [Parameter(Position=1, HelpMessage = "Filename to use when writing SSL certificate to disk")]
  [string]$certFilename,
  [Parameter(Position=2, HelpMessage = "Remote folder to write SSL certificate to")]
  [string]$remoteDirectory,
  [Parameter(Position=3, HelpMessage = "Fully qualified domain name for RDS broker")]
  [string]$rdsFqdn
)

# Split concatenated cert string back into multiple lines
$certFullChainPem = ($certFullChain.Split('|') -join [Environment]::NewLine)

# Write certificate chain to file
$certDir = New-Item -ItemType Directory -Path $remoteDirectory -Force
$certPath = (Join-Path $certDir $certFilename)
if(Test-Path $certPath) {
  Remove-Item -Path $certPath -Force
}
$certFullChainPem | Out-File -FilePath $certPath -Force
Write-Output "Certificate chain written to $certPath"

# Install signed certificate in IIS webserver used by RDS Gateway
# NOTE: Cert:\LocalMachine\My is the default Machine Certificate store and is used by IIS
$certStore = "Cert:\LocalMachine\My"
$cert = Import-Certificate -FilePath "$certPath" -CertStoreLocation $certStore
Write-Output "Certificate chain installed to '$certStore' certificate store"
Write-Output "Certificate thumbprint: $cert.Thumbprint"
# Export full certificate
Add-Type -AssemblyName System.Web
$pfxPassword = ConvertTo-SecureString -String ([System.Web.Security.Membership]::GeneratePassword(20,0)) -AsPlainText -Force
$certExt = (Split-Path -Leaf -Path "$certPath").Split(".")[-1]
if($certExt) {
  # Take all of filename before extension
  $certStem = ((Split-Path -Leaf -Path "$certPath") -split ".$certExt")[0]
} else {
  # No extension to strip so take whole filename
  $certStem = (Split-Path -Leaf -Path "$certPath")
}
$pfxPath = (Join-Path $certDir "$certStem.pfx")
$_ = Get-ChildItem -Path "$certStore\$($cert.Thumbprint)" | Export-PfxCertificate -FilePath $pfxPath -Password $pfxPassword;
Write-Output "PFX public private key pair exported to '$pfxPath', encrypted with strong one-time password"


# Update RDS roles to use new certificate
# Note: If we update VM to Windows Server 2019, we can set this certificate by
# using the new -Thumbprint parameter to reference a certificate in the certificate
# store without needing to export it
#
# The Powershell documentation says available in Server 2016
# Source: https://docs.microsoft.com/en-us/powershell/module/remotedesktop/set-rdcertificate?view=win10-ps
# A TechNet answer says its available in Server 2019
# Source: https://social.technet.microsoft.com/Forums/en-US/1dc4f615-ebe7-4c19-805f-dd243d712bb6/using-setrdcertificate-with-the-thumbprint-parameter-fails-as-quota-parameter-cannot-be-found?forum=winserverTS
#
# It looks like we could even store certificates in Azure KeyVault
# Source: https://www.vembu.com/blog/remote-desktop-services-on-windows-server-2019-whats-new/

Set-RDCertificate -Role RDPublishing -ImportPath "$pfxPath"  -Password $pfxPassword -ConnectionBroker $rdsFqdn -Force
Set-RDCertificate -Role RDRedirector -ImportPath "$pfxPath" -Password $pfxPassword -ConnectionBroker $rdsFqdn -Force
Set-RDCertificate -Role RDWebAccess -ImportPath "$pfxPath" -Password $pfxPassword -ConnectionBroker $rdsFqdn -Force
Set-RDCertificate -Role RDGateway -ImportPath "$pfxPath" -Password $pfxPassword -ConnectionBroker $rdsFqdn -Force
Write-Output "Certificate installed on all RDS roles"

# Import certificate to RDS Web Client
Import-RDWebClientBrokerCert "$certPath"
Publish-RDWebClientPackage -Type Production -Latest
Write-Output "Certificate installed on RDS Web Client"