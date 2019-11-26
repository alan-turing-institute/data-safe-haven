# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Position=0, HelpMessage = "Fully qualified domain name for RDS broker")]
    [string]$rdsFqdn,
    [Parameter(Position=1, HelpMessage = "Thumbprint for the relevant certificate")]
    [string]$certThumbPrint,
    [Parameter(Position=2, HelpMessage = "Remote folder to write SSL certificate to")]
    [string]$remoteDirectory
)

# Set common variables
# --------------------
# NB. Cert:\LocalMachine\My is the default Machine Certificate store and is used by IIS
$certDirLocal = New-Item -ItemType Directory -Path $remoteDirectory -Force
$certStore = "Cert:\LocalMachine\My"

Write-Host "Looking for certificate with thumbprint: $certThumbPrint"
$certificate = Get-ChildItem $certStore | ?{ $_.Thumbprint -eq $certThumbPrint }
if ($certificate -ne $null) {
    Write-Host " [o] Found certificate with correct thumbprint"
} else {
    Write-Host " [x] Failed to find any certificate with the correct thumbprint!"
    throw "Could not load certificate"
}


# Update RDS roles to use new certificate by thumbprint
# -----------------------------------------------------
Write-Host "Updating RDS roles to use new certificate with thumbprint '$($certificate.Thumbprint)'..."
Write-Host "Set-RDCertificate -Role RDPublishing -Thumbprint $($certificate.Thumbprint) -ConnectionBroker $rdsFqdn -Force"


# Set-RDCertificate -Role RDPublishing -Thumbprint $certificate.Thumbprint -ConnectionBroker $rdsFqdn -Force
# $success = $?
# Set-RDCertificate -Role RDRedirector -Thumbprint $certificate.Thumbprint -ConnectionBroker $rdsFqdn -Force
# $success = ($success -and $?)
# Set-RDCertificate -Role RDWebAccess -Thumbprint $certificate.Thumbprint -ConnectionBroker $rdsFqdn -Force
# $success = ($success -and $?)
# Set-RDCertificate -Role RDGateway -Thumbprint $certificate.Thumbprint -ConnectionBroker $rdsFqdn -Force
# $success = ($success -and $?)
# if($success) {
#     Write-Host " [o] Successfully updated RDS roles"
# } else {
#     Write-Host " [o] Failed to update RDS roles!"
#     throw "Could not update RDS roles"
# }


# # # Extract a base64-encoded certificate
# # # ------------------------------------
# # Write-Host "Extracting a base64-encoded certificate..."
# # $derCert = (Join-Path $certDirLocal "letsencrypt_der.cer")
# # $b64Cert = (Join-Path $certDirLocal "letsencrypt_b64.cer")
# # $_ = Export-Certificate -filepath $derCert -cert $certificate -type CERT -Force
# # $success1 = $?
# # $_ = CertUtil -f -encode $derCert $b64Cert
# # $success2 = $?
# # if($success -and $success2) {
# #     Write-Host " [o] Base64-encoded certificate extracted to $b64Cert"
# # } else {
# #     Write-Host " [o] Failed to extract base64-encoded certificate"
# #     throw "Could not extract base64-encoded certificate"
# # }


# # # Import certificate to RDS Web Client
# # # ------------------------------------
# # Write-Host "Importing certificate to RDS Web Client..."
# # Import-RDWebClientBrokerCert $b64Cert
# # Publish-RDWebClientPackage -Type Production -Latest
# # if($?) {
# #     Write-Host " [o] Certificate installed on RDS Web Client"
# # } else {
# #     Write-Host " [o] Failed to install certificate on RDS Web Client"
# # }

# # # # List certificates
# # # # -----------------
# # # Write-Host "Webclient broker certificate:"
# # # Get-RDWebClientBrokerCert
# # # Write-Host "Remote desktop certificate:"
# # # Get-RDCertificate -Role RDGateway -ConnectionBroker $rdsFqdn





















# # # if($?) {
# # #     Write-Host " [o] Certificate installed on RDS Web Client"
# # # } else {
# # #     Write-Host " [o] Failed to install certificate on RDS Web Client"
# # # }



# # # # Export full certificate
# # # # -----------------------
# # # Write-Host "Exporting full certificate as PFX..."
# # # Add-Type -AssemblyName System.Web
# # # $pfxPassword = ConvertTo-SecureString -String ([System.Web.Security.Membership]::GeneratePassword(20,0)) -AsPlainText -Force
# # # $pfxPath = (Join-Path $certDirLocal "letsencrypt.pfx")
# # # if(Test-Path $pfxPath) {
# # #     Remove-Item -Path $pfxPath -Force
# # # }
# # # # $_ = Get-ChildItem -Path "$certStore\$($cert.Thumbprint)" | Export-PfxCertificate -FilePath $pfxPath -Password $pfxPassword;
# # # $certificate
# # # Write-Host $certificate
# # # $certificate | Export-PfxCertificate -FilePath $pfxPath -Password $pfxPassword;
# # # if(Test-Path $pfxPath) {
# # #     Write-Host " [o] PFX public/private key pair exported to '$pfxPath', encrypted with strong one-time password"
# # # } else {
# # #     Write-Host " [x] Failed to export PFX public/private key pair!"
# # #     throw "Could not export PFX public/private key pair"
# # # }



# # # # Write certificate chain to file, removing any previous files
# # # Write-Host "Writing certificate chain to $certPath..."
# # # if(Test-Path $certPath) {
# # #     Remove-Item -Path $certPath -Force
# # # }
# # # # Split concatenated cert string back into multiple lines
# # # ($certFullChain.Split('|') -join [Environment]::NewLine) | Out-File -FilePath $certPath -Force
# # # if(Test-Path $certPath) {
# # #     Write-Host " [o] Certificate chain written to $certPath"
# # # } else {
# # #     Write-Host " [x] Failed to write chain to $certPath!"
# # # }

# # # # Install signed certificate in IIS webserver used by RDS Gateway
# # # Write-Host "Installing signed certificate in IIS webserver used by RDS Gateway..."
# # # $cert = Import-Certificate -FilePath "$certPath" -CertStoreLocation $certStore
# # # Write-Host " [o] Certificate chain installed to '$certStore' certificate store"
# # # Write-Host " [o] Certificate thumbprint: $($cert.Thumbprint)"
# # # # Get-ChildItem cert:\localmachine\My | New-Item -Path IIS:\SslBindings\!443

# # # # Export full certificate
# # # Write-Host "Exporting full certificate..."
# # # Add-Type -AssemblyName System.Web
# # # $pfxPassword = ConvertTo-SecureString -String ([System.Web.Security.Membership]::GeneratePassword(20,0)) -AsPlainText -Force
# # # $certExt = (Split-Path -Leaf -Path "$certPath").Split(".")[-1]
# # # if($certExt) {
# # #     # Take all of filename before extension
# # #     $certStem = ((Split-Path -Leaf -Path "$certPath") -split ".$certExt")[0]
# # # } else {
# # #     # No extension to strip so take whole filename
# # #     $certStem = (Split-Path -Leaf -Path "$certPath")
# # # }
# # # $pfxPath = (Join-Path $certDirLocal "$certStem.pfx")
# # # if(Test-Path $pfxPath) {
# # #     Remove-Item -Path $pfxPath -Force
# # # }
# # # $_ = Get-ChildItem -Path "$certStore\$($cert.Thumbprint)" | Export-PfxCertificate -FilePath $pfxPath -Password $pfxPassword;
# # # if(Test-Path $pfxPath) {
# # #     Write-Host " [o] PFX public private key pair exported to '$pfxPath', encrypted with strong one-time password"
# # # } else {
# # #     Write-Host " [x] Failed to export PFX public private key pair!"
# # # }


# # # Update RDS roles to use new certificate
# # # Note: If we update VM to Windows Server 2019, we can set this certificate by
# # # using the new -Thumbprint parameter to reference a certificate in the certificate
# # # store without needing to export it
# # #
# # # The Powershell documentation says available in Server 2016
# # # Source: https://docs.microsoft.com/en-us/powershell/module/remotedesktop/set-rdcertificate?view=win10-ps
# # # A TechNet answer says its available in Server 2019
# # # Source: https://social.technet.microsoft.com/Forums/en-US/1dc4f615-ebe7-4c19-805f-dd243d712bb6/using-setrdcertificate-with-the-thumbprint-parameter-fails-as-quota-parameter-cannot-be-found?forum=winserverTS
# # #
# # # It looks like we could even store certificates in Azure KeyVault
# # # Source: https://www.vembu.com/blog/remote-desktop-services-on-windows-server-2019-whats-new/
# # # Write-Host "Updating RDS roles to use new certificate..."
# # # Set-RDCertificate -Role RDPublishing -ImportPath "$pfxPath"  -Password $pfxPassword -ConnectionBroker $rdsFqdn -Force
# # # Set-RDCertificate -Role RDRedirector -ImportPath "$pfxPath" -Password $pfxPassword -ConnectionBroker $rdsFqdn -Force
# # # Set-RDCertificate -Role RDWebAccess -ImportPath "$pfxPath" -Password $pfxPassword -ConnectionBroker $rdsFqdn -Force
# # # Set-RDCertificate -Role RDGateway -ImportPath "$pfxPath" -Password $pfxPassword -ConnectionBroker $rdsFqdn -Force
# # # if($?) {
# # #     Write-Host " [o] Successfully updated RDS roles"
# # # } else {
# # #     Write-Host " [o] Failed to update RDS roles!"
# # # }

# # # # Import certificate to RDS Web Client
# # # Write-Host "Importing certificate to RDS Web Client..."
# # # Import-RDWebClientBrokerCert "$certPath"
# # # Publish-RDWebClientPackage -Type Production -Latest
# # # if($?) {
# # #     Write-Host " [o] Certificate installed on RDS Web Client"
# # # } else {
# # #     Write-Host " [o] Failed to install certificate on RDS Web Client"
# # # }
