# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  [Parameter(Position=0, HelpMessage = "Fully qualified domain name of RDS server (e.g. rds.domain.co.uk)")]
  [string]$rdsFqdn,
  [Parameter(Position=1, HelpMessage = "Name of Safe Haven (e.g. 'TEST Safe Haven')")]
  [string]$shmName,
  [Parameter(Position=2, HelpMessage = "Full name of organisation administering Safe Haven (e.g. 'The Alan Turing Institute')")]
  [string]$orgName,
  [Parameter(Position=3, HelpMessage = "Town/City in which organisation is located (e.g. 'London)")]
  [string]$townCity,
  [Parameter(Position=4, HelpMessage = "State/County/Region in which organisation is located (e.g. 'London)")]
  [string]$stateCountyRegion,
  [Parameter(Position=5, HelpMessage = "Two-letter country code in which organisation is located (e.g. 'GB)")]
  [string]$countryCode,
  [Parameter(Position=6, HelpMessage = "Remote folder to write CSR to")]
  [string]$remoteDirectory
)
$keyLength = 2048
$Signature = '$Windows NT$' 
$INF =
@"
[Version]
Signature= "$Signature" 
 
[NewRequest]
Subject = "CN=$rdsFqdn,OU=$shmName,O=T$orgName,L=$townCity,ST=$stateCountyRegion,C=$countryCode"
KeySpec = 1 ; 1=AT_KEYEXCHANGE
KeyLength = $keyLength
Exportable = TRUE   ; Whether private key is exportable 
MachineKeySet = TRUE    ; The key belongs to the local computer account 
SMIME = False
PrivateKeyArchive = FALSE
UserProtected = FALSE
UseExistingKeySet = FALSE
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
RequestType = PKCS10
KeyUsage = 0xa0 ; 0xa0 = "Digital Signature, Key Encipherment"
 
[EnhancedKeyUsageExtension]
 
OID=1.3.6.1.5.5.7.3.1   ; 1.3.6.1.5.5.7.3.1 = Server authentication
"@
$certDir = New-Item -ItemType Directory -Path $remoteDirectory -Force
$dateString = (Get-Date).ToString("yyyyMMdd-HHmmss")
$csrFilestem = "$($dateString)_$($rdsFqdn)"
$csrPath = (Join-Path $certDir "$csrFilestem.csr")
$infPath = (Join-Path $certDir "$csrFilestem.inf")
# Write CSR settings to INF file
$inf | Out-File -Filepath $infPath -Force
# Generate CSR (which is output to disk) 
certreq -New $infPath $csrPath
# Read CSR and write to stdout so it is returned to calling script
$csr = Get-Content -Path $csrPath
Write-Output "-----BEGIN CSR FILESTEM-----$csrFilestem-----END CSR FILESTEM-----"
Write-Output $csr