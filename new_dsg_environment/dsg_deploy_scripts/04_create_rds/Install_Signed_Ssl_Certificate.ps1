param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Email address to associate with the certificate request.")]
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


# Set common variables
# --------------------
$keyvaultName = $config.shm.keyVault.name
$secretName = $config.dsg.keyVault.secretNames.letsEncryptCertificate


# Check for existing certificate in KeyVault
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Checking whether signed certificate already exists in KeyVault..."
$secret = (Get-AzKeyVaultSecret -vaultName $keyvaultName -name $secretName).SecretValueText;
if ($secret -ne $null) {
    $fullChainString = $secret
    Write-Host -ForegroundColor DarkGreen " [o] Loaded certificate from KeyVault '$keyvaultName'"
} else {
    Write-Host -ForegroundColor DarkCyan "Certificate could not be loaded from KeyVault '$keyvaultName'"

    # Set the Posh-ACME server to the appropriate Let's Encrypt endpoint
    # ------------------------------------------------------------------
    if($dryRun){
        Write-Host -ForegroundColor DarkCyan "Using Let's Encrypt staging server (dry-run)"
        Set-PAServer LE_STAGE
    } else {
        Set-PAServer LE_PROD
    }

    # Set Posh-ACME account
    # --------------
    Write-Host -ForegroundColor DarkCyan " [ ] Checking for Posh-ACME account"
    $acct = Get-PAAccount -List -Contact $emailAddress
    if ($acct -eq $null) {
        $account = New-PAAccount -Contact $emailAddress -AcceptTOS
        Write-Host -ForegroundColor DarkGreen " [o] Created new Posh-ACME account with ID: '$($account.id)'"
        $acct = Get-PAAccount -List -Contact $emailAddress
    }
    Write-Host -ForegroundColor DarkGreen " [o] Using Posh-ACME account: $($acct.id)"

    # Get token for DNS subscription
    # ------------------------------
    $azureContext = Set-AzContext -Subscription $config.shm.dns.subscriptionName;
    $token = ($azureContext.TokenCache.ReadItems() | ?{ $_.TenantId -eq $azureContext.Subscription.TenantId } | Select -First 1).AccessToken

    # Test DNS record creation
    # ------------------------
    Write-Host -ForegroundColor DarkCyan "Test that we can interact with DNS records..."
    $testDomain = "dnstest.$($config.dsg.rds.gateway.fqdn)"

    $params = @{
        AZSubscriptionId = $azureContext.Subscription.Id
        AZAccessToken = $token
    }
    Write-Host -ForegroundColor DarkCyan " [ ] DNS record creation..."
    Publish-DnsChallenge $testDomain -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] DNS record creation succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] DNS record creation failed!"
        throw "Unable to create a DNS record for $testDomain!"
    }
    Write-Host -ForegroundColor DarkCyan " [ ] DNS record deletion..."
    Unpublish-DnsChallenge $testDomain -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] DNS record deletion succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] DNS record deletion failed!"
        throw "Unable to delete a DNS record for $testDomain!"
    }

    # Check for existing certificate in Posh-ACME cache
    # -------------------------------------------------
    Write-Host -ForegroundColor DarkCyan "Checking whether signed certificate already exists in Posh-ACME cache..."
    $certificate = Get-PACertificate -MainDomain $config.dsg.rds.gateway.fqdn
    if ($certificate -eq $null) {
        # Generate a certificate signing request
        # --------------------------------------
        Write-Host -ForegroundColor DarkCyan "Generating a certificate signing request..."
        $_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
        $csrDir = New-Item -ItemType Directory -Force -Path "$localDirectory"
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
        $success = $?
        $msg = $result.Value[0].Message
        # Extract CSR filename from result message (to allow easy matching to remote VM for troubleshooting)
        $csrFilestem = ($msg -replace "(?sm).*-----BEGIN CSR FILESTEM-----(.*)-----END CSR FILESTEM-----.*", '$1')
        # Write the CSR to temporary storage
        $csrPath = (Join-Path $csrDir "$csrFilestem.csr")
        # Extract CSR from result message removing any leading spaces or tabs from CSR lines
        $msg -replace("(?sm).*(-----BEGIN NEW CERTIFICATE REQUEST-----)(.*)(-----END NEW CERTIFICATE REQUEST-----).*", '$1$2$3') -replace('(?m)^[ \t]*', '') | Out-File -Filepath $csrPath
        if(-not (Test-Path -Path $csrPath)) {
            $success = $false
        }
        # Output success/failure message
        if ($success) {
            Write-Host -ForegroundColor DarkGreen " [o] CSR saved to '$csrPath'"
        } else {
            Write-Host -ForegroundColor DarkRed " [x] Failed to obtain CSR!"
            throw "Unable to create a signing request!"
        }

        # Send the certificate to be signed
        # ---------------------------------
        Write-Host -ForegroundColor DarkCyan "Sending the CSR to be signed by Let's Encrypt..."
        Publish-DnsChallenge $config.dsg.rds.gateway.fqdn -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
        $azParams = @{
            AZSubscriptionId = $azureContext.Subscription.Id
            AZAccessToken = $token
        }
        Write-Host -ForegroundColor DarkCyan " [ ] Creating certificate..."
        New-PACertificate -CSRPath $csrPath -AcceptTOS -Contact $emailAddress -DnsPlugin Azure -PluginArgs $params -Verbose
        if ($?) {
            Write-Host -ForegroundColor DarkGreen " [o] Certificate creation succeeded"
        } else {
            Write-Host -ForegroundColor DarkRed " [x] Certificate creation failed!"
            throw "Unable to create a certificate for $($config.dsg.rds.gateway.fqdn)!"
        }
        $certificate = Get-PACertificate -MainDomain $config.dsg.rds.gateway.fqdn
    } else {
        $certificate | fl
        Write-Host $certificate
        Write-Host $certificate.RenewAfter
        Write-Host -ForegroundColor DarkGreen " [o] Found certificate which is valid until $($certificate.NotAfter)"
        Submit-Renewal  # this will attempt renewal only if we are after the earliest renewal date
        $certificate = Get-PACertificate -MainDomain $config.dsg.rds.gateway.fqdn
    }
    # Write secret to KeyVault
    Write-Host -ForegroundColor DarkCyan "Storing the signed certificate in the KeyVault for future use..."
    $fullChainString = $(@(Get-Content -Path $certificate.FullChainFile) -join '|')
    $secretValue = (ConvertTo-SecureString $fullChainString -AsPlainText -Force)
    $expiryDate = [DateTime]::ParseExact($certificate.NotAfter, "MM/dd/yyyy HH:mm:ss", $null).AddDays(-30)
    Write-Host -ForegroundColor DarkGreen " [o] setting expiry date to  $expiryDate"
    Set-AzKeyVaultSecret -VaultName $keyvaultName -Name $secretName -SecretValue $secretValue -Expires $expiryDate
}


# Install signed SSL certificate on RDS Gateway
# ---------------------------------------------
if($dryRun){
    Write-Host -ForegroundColor DarkCyan "Dry run does not produce a signed certificate. Skipping installation on RDS Gateway."
} else {
    Write-Host -ForegroundColor DarkCyan "Installing signed SSL certificate on RDS Gateway"
    $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
    # Run remote script
    $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Generate_New_Ssl_Cert" "Install_Signed_Ssl_Cert.ps1"
    $params = @{
        certFullChain = "`"$fullChainString`""
        remoteDirectory = "`"$remoteDirectory`""
        rdsFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
    };
    $result = Invoke-AzVMRunCommand -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $config.dsg.rds.rg `
                                    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
    $success = $?
    Write-Output $result.Value
    if ($success) {
        Write-Host -ForegroundColor DarkGreen " [o] Certificate installation succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Certificate installation failed!"
        throw "Unable to install certificate on $($config.dsg.rds.gateway.vmName)!"
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;




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