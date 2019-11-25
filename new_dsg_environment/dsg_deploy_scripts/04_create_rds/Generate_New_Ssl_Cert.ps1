# param(
#   [Parameter(Position=0, Mandatory = $true, HelpMessage = "SRE ID (usually a number e.g enter '9' for DSG9)")]
#   [string]$sreId,
#   [Parameter(Position=1, Mandatory = $false, HelpMessage = "Local directory (defaults to '~/Certificates')")]
#   [string]$localDirectory = $null,
#   [Parameter(Position=2, Mandatory = $false, HelpMessage = "Remote directory (defaults to '/Certificates')")]
#   [string]$remoteDirectory = $null,
#   [Parameter(Position=3, Mandatory = $false, HelpMessage = "Do a 'dry run' against the Let's Encrypt staging server that doesn't download a certificate")]
#   [bool]$dryRun = $false,
#   [Parameter(Position=4, Mandatory = $false, HelpMessage = "Request a fake certificate from the Let's Encrypt staging server")]
#   [bool]$testCert = $false,
#   [Parameter(Position=5, Mandatory = $false, HelpMessage = "Use a new certbot account to ensure no valid authentication challenge exists (also forces -dryRun to True and -testCert to False)")]
#   [bool]$cleanTest = $false
# )

# Import-Module Az
# Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# if([String]::IsNullOrEmpty($localDirectory)) {
#     $localDirectory = "$HOME/Certificates"
# }
# if([String]::IsNullOrEmpty($remoteDirectory)) {
#     $remoteDirectory = "/Certificates"
# }

# # Get SRE config
# # --------------
# $config = Get-DsgConfig($sreId);
# $originalContext = Get-AzContext


# # Write-Host "Creating CSR on RDS Gateway"
# # Write-Host "---------------------------"
# # # # Create CSR on RDS Gateway and download to local filesystem
# # # $getCsrCmd = (Join-Path $helperScriptsDir "Get_Csr_From_Rds_Gateway.ps1")
# # # $result = Invoke-Expression -Command "$getCsrCmd -sreId $sreId -remoteDirectory '$remoteDirectory' -localDirectory '$localDirectory'"
# # # # Extract path to saved CSR from result message
# # # if($result -is [array]) {
# # #     $csrPath = $result[-1]
# # # } else {
# # #     $csrPath = $result
# # # }


# # # Run remote script
# # $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Generate_New_Ssl_Cert" "Create_Ssl_Csr_Remote.ps1"
# # $params = @{
# #     "rdsFqdn" = "`"$($config.dsg.rds.gateway.fqdn)`""
# #     "shmName" = "`"$($config.shm.name)`""
# #     "orgName" = "`"$($config.shm.organisation.name)`""
# #     "townCity" = "`"$($config.shm.organisation.townCity)`""
# #     "stateCountyRegion" = "`"$($config.shm.organisation.stateCountyRegion)`""
# #     "countryCode" = "`"$($config.shm.organisation.countryCode)`""
# #     "remoteDirectory" = "`"$remoteDirectory`""
# # };
# # $result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName `
# #                                 -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
# # $msg = $result.Value[0].Message
# # # Extract CSR from result message
# # $csr = ($msg -replace "(?sm).*(-----BEGIN NEW CERTIFICATE REQUEST-----)(.*)(-----END NEW CERTIFICATE REQUEST-----).*", '$1$2$3')
# # # Remove any leading spaces or tabs from CSR lines
# # $csr = ($csr -replace '(?m)^[ \t]*', '')
# # # Extract CSR filename from result message (to allow easy matching to remote VM for troubleshooting)
# # $csrFilestem = ($msg -replace "(?sm).*-----BEGIN CSR FILESTEM-----(.*)-----END CSR FILESTEM-----.*", '$1')

# # # Write the CSR to temporary storage
# # $csrDir = New-Item -Path "$localDirectory" -Name "$csrFilestem" -ItemType "directory"
# # $csrPath = (Join-Path $csrDir "$csrFilestem.csr")
# # $csr | Out-File -Filepath $csrPath
# # Write-Host " - CSR saved to '$csrPath'"
# # if(-not (Test-Path -Path $csrPath)) {
# #   throw [System.IO.FileNotFoundException] "$csrPath not found."
# # }

# $csrPath = "/Users/jrobinson/Certificates/20191122-132706_RDS-SRE-TESTSAN.testsandbox.dsgroupdev.co.uk/20191122-132706_RDS-SRE-TESTSAN.testsandbox.dsgroupdev.co.uk.csr"




# # Write-Host "Getting signed SSL certificate"
# # Write-Host "------------------------------"
# # # Use CSR to get signed SSL certificate from Let's Encrypt
# # $signCertCmd = (Join-Path $helperScriptsDir "Get_Signed_Cert_From_Lets_Encrypt.ps1")
# # Invoke-Expression -Command "$signCertCmd -sreId $sreId -csrPath '$csrPath' -dryRun `$dryRun -testCert `$testCert" -OutVariable result
# # # Extract path to saved full chain certificate file from result message
# # if($result -is [array]) {
# #     $certFullChainPath = $result[-1]
# # } else {
# #     $certFullChainPath = $result
# # }

# Write-Host "Getting signed SSL certificate"
# Write-Host "------------------------------"

# if($cleanTest) {
#   $tmpDir = [system.io.path]::GetTempPath()
#   $randSubDirName = -join ((97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_}) # (97..122) is lower case alpha byte numbers in ASCII
#   $tmpDir = New-Item -Path "$tmpDir" -Name "$randSubDirName" -ItemType "directory"
#   $certbotDir = (Join-Path "$tmpDir" "certbot-test")
#   $dryRun = $true
#   $testCert = $false
# } else {
#   $tmpDir = [system.io.path]::GetTempPath()
#   $certbotDir = "$HOME/certbot"
# }

# # # Temporarily switch to DSG subscription
# # $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# $certbotConfigDir = (Join-Path $certbotDir "config")
# $certbotLogDir = (Join-Path $certbotDir "logs")
# $certbotWorkingDir = Split-Path -Parent -Path $csrPath
# $csrExt = (Split-Path -Leaf -Path "$csrPath").Split(".")[-1]
# if($csrExt) {
#   # Take all of filename before extension
#   $csrStem = (Split-Path -Leaf -Path "$csrPath").Split(".$csrExt")[0]
# } else {
#   # No extension to strip so take whole filename
#   $csrStem = (Split-Path -Leaf -Path "$csrPath")
# }
# $certPath = (Join-Path $certbotWorkingDir "$($csrStem)_cert.pem")
# $fullChainPath = (Join-Path $certbotWorkingDir "$($csrStem)_full_chain.pem")
# $chainPath = (Join-Path $certbotWorkingDir "$($csrStem)_chain.pem")

# # Set standard certbot parameters (these are the same for all certs)
# $certbotCmd = "certbot certonly --config-dir '$certbotConfigDir' --logs-dir '$certbotLogDir'"
# # Set cert specific input parameters
# $certbotCmd += " -d $($config.dsg.rds.gateway.fqdn) --csr '$csrPath' --cert-name '$csrStem'"
# # Set cert-specific outoput parameters
# $certbotCmd += " --work-dir '$certbotWorkingDir' --cert-path '$certPath' --fullchain-path '$fullChainPath' --chain-path '$chainPath'"

# # Set certbot authentication options
# $certBotAuthScript = (Join-Path $PSScriptRoot "local_scripts" "Generate_New_Ssl_Cert" "LetsEncrypt_Csr_Dns_Authentication.ps1")
# $params = @{
#     sreId = "`"$sreId`""
#     subscriptionName = "`"$($config.shm.subscriptionName)`""
#     hostName = "`"$($config.dsg.rds.gateway.hostname)`""
#     dnsResourceGroup = "`"$($config.shm.dns.rg)`""
#     sreDomain = "`"$($config.dsg.domain.fqdn)`""
# }
# $certBotAuthCmd = [scriptblock]::create("pwsh `"$certBotAuthScript`" $(&{$args} @params)") -replace(":", "") -replace('"', "'")
# $certbotCmd += " --preferred-challenges 'dns' --manual --manual-auth-hook '$certBotAuthCmd' --manual-public-ip-logging-ok"

# # Force interactive mode to ensure that user is prompted for email address and TOS acceptance
# $certbotCmd += " --force-interactive"

# if($cleanTest){
#   $certbotCmd += " --dry-run --agree-tos -m example@example.com"
# } else {
#   if($dryRun -and $testCert){
#     throw [System.ArgumentException] "Only one of -dryRun and -testCert can be set to True"
#   } elseif ($dryRun -and -not $testCert) {
#     $certbotCmd += " --dry-run"
#   } elseif ($testCert -and -not $dryRun) {
#     $certbotCmd += " --test-cert"
#   }
# }

# Write-Host $certbotCmd
# bash -i -c "$certbotCmd"





# # if($dryRun){
# #     Write-Host "Dry run does not produce a signed certificate. Skipping installation on RDS Gateway."
# # } else {
# #     Write-Host "Installing signed SSL certificate on RDS Gateway"
# #     Write-Host "------------------------------------------------"
# #     # Install signed SSL certificate on RDS Gateway
# #     $installCertCmd = (Join-Path $helperScriptsDir "Install_Signed_Cert_On_Rds_Gateway.ps1")
# #     Invoke-Expression -Command "$installCertCmd -sreId $sreId -certFullChainPath '$certFullChainPath' -remoteDirectory '$remoteDirectory'"
# # }


