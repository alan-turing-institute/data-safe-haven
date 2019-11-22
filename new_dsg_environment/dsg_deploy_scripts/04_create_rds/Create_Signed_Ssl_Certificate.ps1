param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Email address for certificate request.")]
  [string]$emailAddress,
  [Parameter(Position=2, Mandatory = $false, HelpMessage = "Do a 'dry run' against the Let's Encrypt staging server that doesn't download a certificate")]
  [bool]$dryRun = $false,
  [Parameter(Position=3, Mandatory = $false, HelpMessage = "Local directory (defaults to '~/Certificates')")]
  [string]$localDirectory = "$HOME/Certificates",
  [Parameter(Position=4, Mandatory = $false, HelpMessage = "Remote directory (defaults to '/Certificates')")]
  [string]$remoteDirectory = "/Certificates"
)

# Ensure that Posh-ACME is installed for current user
if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
    Install-Module -Name Posh-ACME -Scope CurrentUser -Force
}

# Import modules
Import-Module Posh-ACME
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force


# Get SRE config
# --------------
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext


# Generate a certificate signing request
# --------------------------------------
Write-Host -ForegroundColor DarkCyan "Generating a certificate signing request..."
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Generate_New_Ssl_Cert" "Create_Ssl_Csr.ps1"
$params = @{
    "rdsFqdn" = "`"$($config.dsg.rds.gateway.fqdn)`""
    "shmName" = "`"$($config.shm.name)`""
    "orgName" = "`"$($config.shm.organisation.name)`""
    "townCity" = "`"$($config.shm.organisation.townCity)`""
    "stateCountyRegion" = "`"$($config.shm.organisation.stateCountyRegion)`""
    "countryCode" = "`"$($config.shm.organisation.countryCode)`""
    "remoteDirectory" = "`"$remoteDirectory`""
};
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
Write-Host $result
$msg = $result.Value[0].Message
Write-Host "msg: $msg"
# Extract CSR from result message
$csr = ($msg -replace "(?sm).*(-----BEGIN NEW CERTIFICATE REQUEST-----)(.*)(-----END NEW CERTIFICATE REQUEST-----).*", '$1$2$3')
# Remove any leading spaces or tabs from CSR lines
$csr = ($csr -replace '(?m)^[ \t]*', '')
Write-Host "csr: $csr"
# Extract CSR filename from result message (to allow easy matching to remote VM for troubleshooting)
$csrFilestem = ($msg -replace "(?sm).*-----BEGIN CSR FILESTEM-----(.*)-----END CSR FILESTEM-----.*", '$1')
Write-Host "csrFilestem: $csrFilestem"
# Write the CSR to temporary storage
$csrDir = New-Item -Path "$localDirectory" -Name "$csrFilestem" -ItemType "directory"
$csrPath = (Join-Path $csrDir "$csrFilestem.csr")
$csr | Out-File -Filepath $csrPath
Write-Host " - CSR saved to '$csrPath'"
if(-not (Test-Path -Path $csrPath)) {
  throw [System.IO.FileNotFoundException] "$csrPath not found."
}
$csrPath = "/Users/jrobinson/Certificates/20191122-132706_RDS-SRE-TESTSAN.testsandbox.dsgroupdev.co.uk/20191122-132706_RDS-SRE-TESTSAN.testsandbox.dsgroupdev.co.uk.csr"



# Set the Posh-ACME server to the appropriate Let's Encrypt endpoint
# ------------------------------------------------------------------
if($dryRun){
    Set-PAServer LE_STAGE
} else {
    Write-Host "not a dry run: fix this when testing is over"
    Set-PAServer LE_STAGE
}

# # Set PA account
# # --------------
# $acct = Get-PAAccount -List -Contact $emailAddress
# if ($acct -eq $null) {
#     $account = New-PAAccount -Contact $emailAddress -AcceptTOS
#     Write-Host "Created new PA account with ID: '$($account.id)'"
#     Set-PAAccount -ID $account.id
#     $acct = Get-PAAccount -List -Contact $emailAddress
# }
# Write-Host -ForegroundColor DarkCyan "Using PoshACME account: $acct"


# # Get token for DNS subscription
# # ------------------------------
# $azureContext = Set-AzContext -Subscription $config.shm.dns.subscriptionName;
# $token = ($azureContext.TokenCache.ReadItems() | ?{ $_.TenantId -eq $azureContext.Subscription.TenantId } | Select -First 1).AccessToken


# # Test DNS record creation
# # ------------------------
# Write-Host -ForegroundColor DarkCyan "Test that we can interact with DNS records..."
# $testDomain = "dnstest.$($config.dsg.rds.gateway.fqdn)"

# $params = @{
#   AZSubscriptionId = $azureContext.Subscription.Id
#   AZAccessToken = $token
# }
# Write-Host -ForegroundColor DarkCyan " [ ] DNS record creation..."
# Publish-DnsChallenge $testDomain -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
# if ($?) {
#     Write-Host -ForegroundColor DarkGreen " [o] DNS record creation succeeded"
# } else {
#     Write-Host -ForegroundColor DarkRed " [x] DNS record creation failed!"
#     throw "Unable to create a DNS record for $testDomain!"
# }
# Write-Host -ForegroundColor DarkCyan " [ ] DNS record deletion..."
# Unpublish-DnsChallenge $testDomain -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
# if ($?) {
#     Write-Host -ForegroundColor DarkGreen " [o] DNS record deletion succeeded"
# } else {
#     Write-Host -ForegroundColor DarkRed " [x] DNS record deletion failed!"
#     throw "Unable to delete a DNS record for $testDomain!"
# }



# # Check for existing certificate
# # ------------------------------
# Write-Host -ForegroundColor DarkCyan "Checking whether certificate exists for $($config.dsg.rds.gateway.fqdn)..."
# $certificate = Get-PACertificate -MainDomain $config.dsg.rds.gateway.fqdn
# if ($certificate -eq $null) {
#     Publish-DnsChallenge $config.dsg.rds.gateway.fqdn -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
#     Write-Host -ForegroundColor DarkCyan "No certificate found. Creating a new certificate signed by Let's Encrypt..."
#     $azParams = @{
#     AZSubscriptionId = $azureContext.Subscription.Id
#     AZAccessToken = $token
#     }
#     Write-Host -ForegroundColor DarkCyan " [ ] Creating certificate..."
#     # New-PACertificate $config.dsg.rds.gateway.fqdn -AcceptTOS -Contact $emailAddress -DnsPlugin Azure -PluginArgs $params -Verbose
#     New-PACertificate -CSRPath $csrPath -AcceptTOS -Contact $emailAddress -DnsPlugin Azure -PluginArgs $params -Verbose
#     if ($?) {
#         Write-Host -ForegroundColor DarkGreen " [o] Certificate creation succeeded"
#     } else {
#         Write-Host -ForegroundColor DarkRed " [x] Certificate creation failed!"
#         throw "Unable to create a certificate for $($config.dsg.rds.gateway.fqdn)!"
#     }
# } else {
#     Write-Host -ForegroundColor DarkGreen " [o] Found certificate which is valid until $($certificate.NotAfter)."
#     # Write-Host -ForegroundColor DarkCyan "Attempting renewal..."
#     # Submit-Renewal
# }
# $certificate = Get-PACertificate -MainDomain $config.dsg.rds.gateway.fqdn
# # $order = Get-PAOrder -MainDomain $config.dsg.rds.gateway.fqdn
# # $order | fl
# # $order

# # $certificate.FullChainFile
# # cert.cer	chain.cer	fullchain.cer	order.json	request.csr

# # # Install signed SSL certificate on RDS Gateway
# # # ---------------------------------------------
# # # if($dryRun){
# # #     Write-Host "Dry run does not produce a signed certificate. Skipping installation on RDS Gateway."
# # # } else {
# #     Write-Host "Installing signed SSL certificate on RDS Gateway"
# #     Write-Host "------------------------------------------------"
# #     # Install signed SSL certificate on RDS Gateway
# #     $installCertCmd = (Join-Path $helperScriptsDir "Install_Signed_Cert_On_Rds_Gateway.ps1")
# #     Invoke-Expression -Command "$installCertCmd -sreId $sreId -certFullChainPath '$certFullChainPath' -remoteDirectory '$remoteDirectory'"
# # # }

# # Install signed SSL certificate on RDS Gateway
# # ---------------------------------------------
# Write-Host "Installing signed SSL certificate on RDS Gateway"
# $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
# $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Generate_New_Ssl_Cert" "Install_Signed_Ssl_Cert_Remote.ps1"
# $params = @{
#     certFullChain = "`"$(@(Get-Content -Path $certificate.FullChainFile) -join '|')`""
#     certFilename = "`"$(Split-Path -Leaf -Path $certificate.FullChainFile)`""
#     remoteDirectory = "/Certificates"
#     rdsFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
# };
# Invoke-AzVMRunCommand -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $config.dsg.rds.rg `
#                       -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params






# # # Import the PoshACME certificate to the KeyVault
# # # -----------------------------------------------
# # Write-Host -ForegroundColor DarkCyan "Importing the PoshACME certificate to KeyVault $($config.dsg.keyVault.name)..."
# # $azureContext = Set-AzContext -Subscription $config.dsg.subscriptionName;
# # $existingCertificate = Get-AzKeyVaultCertificate -VaultName $config.dsg.keyVault.name -Name $config.dsg.keyVault.secretNames.letsEncryptCertificate
# # if ($certificate.Thumbprint -eq $existingCertificate.Thumbprint) {
# #     Write-Host -ForegroundColor DarkGreen " [o] Skipping this step as the thumbprints are identical"
# # } else {
# #     Import-AzKeyVaultCertificate -VaultName $config.dsg.keyVault.name -Name $config.dsg.keyVault.secretNames.letsEncryptCertificate -FilePath $certificate.PfxFile -Password $certificate.PfxPass
# #     if ($?) {
# #         Write-Host -ForegroundColor DarkGreen " [o] Certificate import succeeded"
# #     } else {
# #         Write-Host -ForegroundColor DarkRed " [x] Certificate import failed!"
# #         throw "Unable to import certificate!"
# #     }
# # }


# # # Add the certificate to the RDS gateway
# # # --------------------------------------
# # Write-Host -ForegroundColor DarkCyan "Adding the certificate to the RDS gateway..."
# # $certURL = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.keyVault.secretNames.letsEncryptCertificate).id
# # $vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName
# # $vaultId = (Get-AzKeyVault -ResourceGroupName $config.dsg.keyVault.rg -VaultName $config.dsg.keyVault.name).ResourceId
# # $updatedVm = Add-AzVMSecret -VM $vm -SourceVaultId $vaultId -CertificateStore "My" -CertificateUrl $certURL
# # Update-AzVM -ResourceGroupName $config.dsg.rds.rg -VM $updatedVm
# # if ($?) {
# #     Write-Host -ForegroundColor DarkGreen " [o] Uploading certificate to RDS gateway succeeded"
# # } else {
# #     Write-Host -ForegroundColor DarkRed " [x] Uploading certificate to RDS gateway failed!"
# #     throw "Unable to upload certificate!"
# # }


# # # # Configure IIS to use the certificate
# # # # ------------------------------------
# # # Write-Host -ForegroundColor DarkCyan "Configuring IIS to use the certificate..."
# # # $PublicSettings = '{
# # #     "fileUris":["https://raw.githubusercontent.com/Azure-Samples/compute-automation-configurations/master/secure-iis.ps1"],
# # #     "commandToExecute":"powershell -ExecutionPolicy Unrestricted -File secure-iis.ps1"
# # # }'
# # # Set-AzVMExtension -ResourceGroupName $config.dsg.rds.rg `
# # #     -ExtensionName "IIS" `
# # #     -VMName $config.dsg.rds.gateway.vmName `
# # #     -Location $config.dsg.location `
# # #     -Publisher "Microsoft.Compute" `
# # #     -ExtensionType "CustomScriptExtension" `
# # #     -TypeHandlerVersion 1.8 `
# # #     -SettingString $publicSettings
# # # if ($?) {
# # #     Write-Host -ForegroundColor DarkGreen " [o] IIS configuration succeeded"
# # # } else {
# # #     Write-Host -ForegroundColor DarkRed " [x] IIS configuration failed!"
# # #     throw "Unable to upload certificate!"
# # # }



# # # # Configure IIS to use the certificate
# # # # ------------------------------------
# # # $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;


# # # # Run remote script
# # # $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Generate_New_Ssl_Cert" "Install_Signed_Ssl_Cert_Remote.ps1"
# # # $certFilename = (Split-Path -Leaf -Path $certFullChainPath)
# # # $certFullChain = (@(Get-Content -Path $certFullChainPath) -join "|")

# # # $params = @{
# # #     certFullChain = "`"$certFullChain`""
# # #     certFilename = "`"$certFilename`""
# # #     remoteDirectory = "`"$remoteDirectory`""
# # #     rdsFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
# # # };
# # # Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName `
# # #     -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
# # #     -Parameter $params

# # # # Switch back to previous subscription
# # # $_ = Set-AzContext -Context $prevContext;