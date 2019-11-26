param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $false, HelpMessage = "Email address to associate with the certificate request.")]
  [string]$emailAddress = "dsgbuild@turing.ac.uk",
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
$keyvaultName = $config.dsg.keyVault.name
# $secretName = $config.dsg.keyVault.secretNames.letsEncryptCertificate
$certificateName = $config.dsg.keyVault.secretNames.letsEncryptCertificate


# Check for existing certificate in KeyVault
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Checking whether signed certificate already exists in KeyVault..."
$kvCertificate = Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName
$requestCertificate = $false
# Determine whether a renewal is needed
if ($kvCertificate -eq $null) {
    Write-Host -ForegroundColor DarkCyan "Certificate could not be loaded from KeyVault '$keyvaultName'"
    $requestCertificate = $true
} else {
    $renewalDate = [DateTime]::ParseExact($kvCertificate.Certificate.NotAfter, "MM/dd/yyyy HH:mm:ss", $null).AddDays(-30)
    Write-Host -ForegroundColor DarkGreen " [o] Loaded certificate from KeyVault '$keyvaultName' with earliest renewal date $($renewalDate.ToString('dd MMM yyyy'))"
    if ($(Get-Date) -ge $renewalDate) {
        $requestCertificate = $true
    }
}


# Request a new/updated certificate
# ---------------------------------
if ($requestCertificate) {
    Write-Host -ForegroundColor DarkCyan "Preparing to request a new certificate..."
    # Set the Posh-ACME server to the appropriate Let's Encrypt endpoint
    # ------------------------------------------------------------------
    if($dryRun){
        Write-Host -ForegroundColor DarkCyan "Using Let's Encrypt staging server (dry-run)"
        Set-PAServer LE_STAGE
    } else {
        Write-Host -ForegroundColor DarkCyan "Using Let's Encrypt production server!"
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
    $token = ($azureContext.TokenCache.ReadItems() | ?{ ($_.TenantId -eq $azureContext.Subscription.TenantId) -and ($_.Resource -eq "https://management.core.windows.net/") } | Select -First 1).AccessToken

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
    $_ = Set-AzContext -Subscription $config.dsg.subscriptionName;

    # Check for existing certificate in Posh-ACME cache
    # -------------------------------------------------
    Write-Host -ForegroundColor DarkCyan "Checking whether signed certificate already exists in Posh-ACME cache..."
    $paCertificate = Get-PACertificate -MainDomain $config.dsg.rds.gateway.fqdn
    if ($paCertificate -eq $null) {
        # Generate a certificate signing request in the KeyVault
        # ------------------------------------------------------
        $csrPath = (New-TemporaryFile).FullName + ".csr"
        Write-Host -ForegroundColor DarkCyan "Generating a certificate signing request at '$csrPath' to be signed by Let's Encrypt..."
        $SubjectName = "CN=$($config.dsg.rds.gateway.fqdn),OU=$($config.shm.name),O=$($config.shm.organisation.name),L=$($config.shm.organisation.townCity),S=$($config.shm.organisation.stateCountyRegion),C=$($config.shm.organisation.countryCode)"
        $manualPolicy = New-AzKeyVaultCertificatePolicy -ValidityInMonths 1 -IssuerName "Unknown" -SubjectName "$SubjectName"
        $manualPolicy.Exportable = $true
        $certificateOperation = Add-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName -CertificatePolicy $manualPolicy
        $success = $?
        "-----BEGIN CERTIFICATE REQUEST-----`n" + $certificateOperation.CertificateSigningRequest + "`n-----END CERTIFICATE REQUEST-----" | Out-File -FilePath $csrPath
        if ($?) {
            Write-Host -ForegroundColor DarkGreen " [o] CSR creation succeeded"
        } else {
            Write-Host -ForegroundColor DarkRed " [x] CSR creation failed!"
            throw "Unable to create a certificate signing request for $($config.dsg.rds.gateway.fqdn)!"
        }
        Get-AzKeyVaultCertificatePolicy -VaultName $keyvaultName -Name $certificateName

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
        $paCertificate = Get-PACertificate -MainDomain $config.dsg.rds.gateway.fqdn
    } else {
        Write-Host -ForegroundColor DarkGreen " [o] Found certificate which is valid until $($paCertificate.NotAfter)"
        Submit-Renewal  # this will attempt renewal only if we are after the earliest renewal date
        $paCertificate = Get-PACertificate -MainDomain $config.dsg.rds.gateway.fqdn
    }

    # Import signed certificate
    # -------------------------
    Write-Host -ForegroundColor DarkCyan "Importing signed certificate into KeyVault '$keyvaultName'..."
    $kvCertificate = Import-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName -FilePath $paCertificate.CertFile
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] Certificate import succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Certificate import failed!"
        throw "Unable to import certificate to $keyvaultName!"
    }
}


# Install signed SSL certificate on RDS Gateway
# ---------------------------------------------
if($dryRun){
#     Write-Host -ForegroundColor DarkCyan "Dry run does not produce a signed certificate. Skipping installation on RDS Gateway."
# } else {

    # Add the KeyVault certificate to the gateway VM
    Write-Host -ForegroundColor DarkCyan "Adding signed SSL certificate to RDS Gateway VM"
    $vaultId = (Get-AzKeyVault -ResourceGroupName $config.dsg.keyVault.rg -VaultName $keyVaultName).ResourceId
    $secretURL = (Get-AzKeyVaultSecret -VaultName $keyvaultName -Name $certificateName).id
    $gatewayVm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName | Remove-AzVMSecret
    $gatewayVm = Add-AzVMSecret -VM $gatewayVm -SourceVaultId $vaultId -CertificateStore "My" -CertificateUrl $secretURL
    $_ = Update-AzVM -ResourceGroupName $config.dsg.rds.rg -VM $gatewayVm
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] Adding certificate succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Adding certificate failed!"
        throw "Unable to add certificate to $($config.dsg.rds.gateway.vmName)!"
    }

    Write-Host -ForegroundColor DarkCyan "Configuring RDS Gateway VM to use signed certificate"
    $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
    # Run remote script
    $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Generate_New_Ssl_Cert" "Install_Signed_Ssl_Cert.ps1"
    $params = @{
        rdsFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
        certThumbPrint = "`"$($kvCertificate.Thumbprint)`""
        remoteDirectory = "`"$remoteDirectory`""
    };
    $result = Invoke-AzVMRunCommand -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $config.dsg.rds.rg `
                                    -CommandId "RunPowerShellScript" -ScriptPath $scriptPath -Parameter $params;
    $success = $?
    Write-Output $result.Value
    if ($success) {
        Write-Host -ForegroundColor DarkGreen " [o] Certificate installation succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Certificate installation failed!"
        throw "Unable to install certificate on $($config.dsg.rds.gateway.vmName)!"
    }

    # # Remove the KeyVault certificate from the gateway VM
    # $updatedVM = Add-AzVMSecret -VM $vm -SourceVaultId $vaultId -CertificateStore "My" -CertificateUrl $certURL
    # Update-AzVM -ResourceGroupName $config.dsg.rds.rg -VM $updatedVM
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