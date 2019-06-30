param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $false, HelpMessage = "Enter working directory (defaults to a temp direcotry)")]
  [string]$workingDirectory = $null,
  [Parameter(Position=2, Mandatory = $false, HelpMessage = "Flag to do a test 'dry run' against the Let's Encrypt staging servers (also uses a different local certbot folder)")]
  [bool]$dryRun = $false
)

if([String]::IsNullOrEmpty($workingDirectory)) {
    $workingDirectory = [system.io.path]::GetTempPath()
}

$helperScriptsDir = (Join-Path $PSScriptRoot "helper_scripts" "Create_Or_Renew_Ssl_Cert_Helper_Scripts" "local_scripts")

# Create CSR on RDS Gateway and download to local filesystem
$getCsrCmd = (Join-Path $helperScriptsDir "Get_Csr_From_Rds_Gateway.ps1")
$result = Invoke-Expression -Command "$getCsrCmd -dsgId $dsgId -workingDirectory $workingDirectory"

# Extract path to saved CSR from result message
if($result -is [array]) {
    $csrPath = $result[-1]
} else {
    $csrPath = $result
}

# Use CSR to get signed SSL certificate from Let's Encrypt
$signCertCmd = (Join-Path $helperScriptsDir "Get_LetsEncrypt_Cert_From_Csr.ps1")
$result = Invoke-Expression -Command "$signCertCmd -dsgId $dsgId -csrPath $csrPath -dryRun `$dryRun"