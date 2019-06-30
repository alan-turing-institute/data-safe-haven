param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter path to CSR file generated on DSG RDS Gateway VM")]
  [string]$csrPath,
  [Parameter(Position=2, Mandatory = $false, HelpMessage = "Flag to do a test 'dry run' against the Let's Encrypt staging servers (also uses a different local certbot folder)")]
  [bool]$dryRun = $false

)

if(-not (Test-Path -Path $csrPath)) {
  throw [System.IO.FileNotFoundException] "$csrPath not found."
}

if($dryRun) {
  $tmpDir = [system.io.path]::GetTempPath()
  $randSubDirName = [System.IO.Path]::GetRandomFileName().Split('.')[0]
  $tmpDir = New-Item -Path "$tmpDir" -Name "$randSubDirName" -ItemType "directory"
  $certbotDir = (Join-Path "$tmpDir" "certbot-test")
} else {
  $tmpDir = [system.io.path]::GetTempPath()
  $certbotDir = (Join-Path "~" "certbot")
}

Import-Module Az
Import-Module (Join-Path $PSScriptRoot ".." ".." ".." ".." "DsgConfig.psm1") -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

$certbotConfigDir = (Join-Path $certbotDir "config")
$certbotLogDir = (Join-Path $certbotDir "log")
$certbotWorkingDir = Split-Path -Parent -Path $csrPath
$csrExt = (Split-Path -Leaf -Path $csrPath).Split(".")[-1]
if($csrExt) {
  # Take all of filename before to extenstion
  $csrStem = (Split-Path -Leaf -Path $csrPath).Split(".$csrExt")[0]
} else {
  # No extension to strip so take whole filename
  $csrStem = (Split-Path -Leaf -Path $csrPath)[0]
}
$certPath = (Join-Path $certbotWorkingDir "$($csrStem)_cert.pem")
$fullChainPath = (Join-Path $certbotWorkingDir "$($csrStem)_full_chain.pem")
$chainPath = (Join-Path $certbotWorkingDir "$($csrStem)_chain.pem")

# Set standard certbot parameters (these are the same for all certs)
$certbotCmd = "certbot certonly --config-dir '$certbotConfigDir' --logs-dir '$certbotLogDir'"

# Set cert specific input parameters
$certbotCmd += " -d $($config.dsg.rds.gateway.fqdn) --csr '$csrPath' --cert-name '$csrStem'"
# Set cert-specific outoput parameters
$certbotCmd += " --work-dir '$certbotWorkingDir' --cert-path '$certPath' --fullchain-path '$fullChainPath' --chain-path '$chainPath'"

# Set certbot authentication options
$certBotAuthScript = (Join-Path $PSScriptRoot "LetsEncrypt_Csr_Dns_Authentication.ps1")
$certBotAuthCmd = "pwsh `"$certBotAuthScript`" -dsgId $dsgId"
$certbotCmd += " --preferred-challenges 'dns' --manual --manual-auth-hook '$certBotAuthCmd' --manual-public-ip-logging-ok"

if($dryRun) {
  $certbotCmd += " --dry-run --agree-tos -m example@example.com"
}

bash -c "$certbotCmd"

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;