param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $false, HelpMessage = "Local directory (defaults to '~/Certificates')")]
  [string]$localDirectory = $null,
  [Parameter(Position=1, Mandatory = $false, HelpMessage = "Remote directory (defaults to '/Certificates')")]
  [string]$remoteDirectory = $null,
  [Parameter(Position=3, Mandatory = $false, HelpMessage = "Do a 'dry run' against the Let's Encrypt staging server that doesn't download a certificate")]
  [bool]$dryRun = $false,
  [Parameter(Position=4, Mandatory = $false, HelpMessage = "Request a fake certificate from the Let's Encrypt staging server")]
  [bool]$testCert = $false
)

if([String]::IsNullOrEmpty($localDirectory)) {
    $localDirectory = "~/Certificates"
}
if([String]::IsNullOrEmpty($remoteDirectory)) {
    $remoteDirectory = "/Certificates"
}

$helperScriptsDir = (Join-Path $PSScriptRoot "helper_scripts" "Create_Or_Renew_Ssl_Cert_Helper_Scripts" "local_scripts")

Write-Host "Creating CSR on RDS Gateway"
Write-Host "---------------------------"
# Create CSR on RDS Gateway and download to local filesystem
$getCsrCmd = (Join-Path $helperScriptsDir "Get_Csr_From_Rds_Gateway.ps1")
$result = Invoke-Expression -Command "$getCsrCmd -dsgId $dsgId -remoteDirectory '$remoteDirectory' -localDirectory '$localDirectory'"
# Extract path to saved CSR from result message
if($result -is [array]) {
    $csrPath = $result[-1]
} else {
    $csrPath = $result
}

Write-Host "Getting signed SSL certificate"
Write-Host "------------------------------"
# Use CSR to get signed SSL certificate from Let's Encrypt
$signCertCmd = (Join-Path $helperScriptsDir "Get_Signed_Cert_From_Lets_Encrypt.ps1")
$result = Invoke-Expression -Command "$signCertCmd -dsgId $dsgId -csrPath '$csrPath' -dryRun `$dryRun -testCert `$testCert"
# Extract path to saved full chain certificate file from result message
if($result -is [array]) {
    $certPath = $result[-1]
} else {
    $certPath = $result
}

Write-Host "Installing signed SSL certificate on RDS Gateway"
Write-Host "------------------------------------------------"
# Install signed SSL certificate on RDS Gateway
$installCertCmd = (Join-Path $helperScriptsDir "Install_Signed_Cert_On_Rds_Gateway.ps1")
Invoke-Expression -Command "$installCertCmd -dsgId $dsgId -certPath '$certPath' -remoteDirectory '$remoteDirectory'"