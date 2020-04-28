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
$certificate = Get-ChildItem $certStore | Where-Object { $_.Thumbprint -eq $certThumbPrint }
if ($null -ne $certificate) {
    Write-Host " [o] Found certificate with correct thumbprint"
} else {
    Write-Host " [x] Failed to find any certificate with the correct thumbprint!"
    throw "Could not load certificate"
}


# Update RDS roles to use new certificate by thumbprint
# -----------------------------------------------------
Write-Host "Updating RDS roles to use new certificate..."
Set-RDCertificate -Role RDPublishing -Thumbprint $certificate.Thumbprint -ConnectionBroker $rdsFqdn -ErrorAction Stop -Force
$success = $?
Set-RDCertificate -Role RDRedirector -Thumbprint $certificate.Thumbprint -ConnectionBroker $rdsFqdn -ErrorAction Stop -Force
$success = $success -and $?
Set-RDCertificate -Role RDWebAccess -Thumbprint $certificate.Thumbprint -ConnectionBroker $rdsFqdn -ErrorAction Stop -Force
$success = $success -and $?
Set-RDCertificate -Role RDGateway -Thumbprint $certificate.Thumbprint -ConnectionBroker $rdsFqdn -ErrorAction Stop -Force
$success = $success -and $?
Write-Host "Currently installed certificates:"
Get-RDCertificate -ConnectionBroker $rdsFqdn
if($success) {
    Write-Host " [o] Successfully updated RDS roles"
} else {
    Write-Host " [x] Failed to update RDS roles!"
    throw "Could not update RDS roles"
}

# Extract a base64-encoded certificate
# ------------------------------------
Write-Host "Extracting a base64-encoded certificate..."
$derCert = (Join-Path $certDirLocal "letsencrypt_der.cer")
$b64Cert = (Join-Path $certDirLocal "letsencrypt_b64.cer")
$_ = Export-Certificate -filepath $derCert -cert $certificate -type CERT -Force
$success = $?
$_ = CertUtil -f -encode $derCert $b64Cert
$success = $success -and $?
if ($success) {
    Write-Host " [o] Base64-encoded certificate extracted to $b64Cert"
} else {
    Write-Host " [x] Failed to extract base64-encoded certificate"
    throw "Could not extract base64-encoded certificate"
}


# Import certificate to RDS Web Client
# ------------------------------------
Write-Host "Importing certificate to RDS Web Client..."
Import-RDWebClientBrokerCert $b64Cert
Publish-RDWebClientPackage -Type Production -Latest
if ($?) {
    Write-Host " [o] Certificate installed on RDS Web Client"
} else {
    Write-Host " [x] Failed to install certificate on RDS Web Client"
    throw "Failed to install certificate on RDS Web Client"
}


# Check certificates
# ------------------
Write-Host "Checking webclient broker certificate..."
$webclientThumbprint = (Get-RDWebClientBrokerCert).Thumbprint
if ($webclientThumbprint -eq $certThumbPrint) {
    Write-Host " [o] Webclient broker certificate has the correct thumbprint: '$webclientThumbprint'"
} else {
    Write-Host " [x] Webclient broker certificate has incorrect thumbprint: '$webclientThumbprint'"
    throw "Webclient broker certificate has incorrect thumbprint"
}
Write-Host "Checking RDGateway certificate..."
$gatewayThumbprint = (Get-RDCertificate -Role RDGateway -ConnectionBroker $rdsFqdn).Thumbprint
if ($gatewayThumbprint -eq $certThumbPrint) {
    Write-Host " [o] RDGateway certificate has the correct thumbprint: '$gatewayThumbprint'"
} else {
    Write-Host " [x] RDGateway certificate has incorrect thumbprint: '$gatewayThumbprint'"
    throw "RDGateway certificate has incorrect thumbprint"
}
