param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $false, HelpMessage = "Email address to associate with the certificate request.")]
    [string]$emailAddress = "dsgbuild@turing.ac.uk",
    [Parameter(Mandatory = $false, HelpMessage = "Do a 'dry run' against the Let's Encrypt staging server.")]
    [switch]$dryRun,
    [Parameter(Mandatory = $false, HelpMessage = "Force the installation step even for dry runs.")]
    [switch]$forceInstall,
    [Parameter(Mandatory = $false, HelpMessage = "Remote directory (defaults to '/Certificates')")]
    [string]$remoteDirectory = "/Certificates"
)

# Import modules
# --------------
Import-Module Az.Accounts
Import-Module Az.Compute
Import-Module Az.KeyVault
Import-Module $PSScriptRoot/../../common/Configuration -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop


# Check that we are authenticated in Azure
# ----------------------------------------
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
if (-not $azProfile.Accounts.Count) {
    Add-LogMessage -Level Fatal "Could not find a valid AzProfile, please run Connect-AzAccount!"
}

# Get config and original context
# -------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -Subscription $config.sre.subscriptionName -ErrorAction Stop


# Set certificate name
# --------------------
$certificateName = $config.sre.keyVault.secretNames.letsEncryptCertificate
if ($dryRun) { $certificateName += "-dryrun" }


# Check for existing certificate in Key Vault
# -------------------------------------------
Add-LogMessage -Level Info "[ ] Checking whether signed certificate '$certificateName' already exists in Key Vault..."
$kvCertificate = Get-AzKeyVaultCertificate -VaultName $config.sre.keyVault.name -Name $certificateName
$requestCertificate = $false


# Determine whether a certificate request is needed
# -------------------------------------------------
if ($null -eq $kvCertificate) {
    Add-LogMessage -Level Info "No certificate found in Key Vault '$($config.sre.keyVault.name)'"
    $requestCertificate = $true
} else {
    try {
        $renewalDate = [datetime]::ParseExact($kvCertificate.Certificate.NotAfter, "MM/dd/yyyy HH:mm:ss", $null).AddDays(-30)
        Add-LogMessage -Level Success "Loaded certificate from Key Vault '$($config.sre.keyVault.name)' with earliest renewal date $($renewalDate.ToString('dd MMM yyyy'))"
    } catch [System.Management.Automation.MethodInvocationException] {
        $renewalDate = $null
    }
    if (($null -eq $renewalDate) -or ($(Get-Date) -ge $renewalDate)) {
        Add-LogMessage -Level Warning "Removing outdated certificate from Key Vault '$($config.sre.keyVault.name)'..."
        $null = Remove-AzKeyVaultCertificate -VaultName $config.sre.keyVault.name -Name $certificateName -Force -ErrorAction SilentlyContinue
        Start-Sleep 5  # ensure that the removal command has registered before attempting to purge
        $null = Remove-AzKeyVaultCertificate -VaultName $config.sre.keyVault.name -Name $certificateName -InRemovedState -Force -ErrorAction SilentlyContinue
        $requestCertificate = $true
    }
}


# Request a new certificate
# -------------------------
if ($requestCertificate) {
    Add-LogMessage -Level Info "Preparing to request a new certificate..."
    $baseFqdn = $config.sre.domain.fqdn
    $rdsFqdn = $config.sre.rds.gateway.fqdn

    # Get token for DNS subscription
    # ------------------------------
    $azureContext = Set-AzContext -Subscription $config.shm.dns.subscriptionName -ErrorAction Stop
    if ($azureContext.TokenCache) {
        # Old method: pre Az.Accounts 2.0
        $token = ($azureContext.TokenCache.ReadItems() | Where-Object { ($_.TenantId -eq $azureContext.Subscription.TenantId) -and ($_.Resource -eq "https://management.core.windows.net/") } | Select-Object -First 1).AccessToken
    } else {
        # New method: hopefully soon to be superceded by a dedicated Get-AzAccessToken cmdlet (https://github.com/Azure/azure-powershell/issues/13337)
        $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
        $token = $profileClient.AcquireAccessToken($azureContext.Tenant.TenantId).AccessToken
    }
    $null = Set-AzContext -Subscription $config.sre.subscriptionName -ErrorAction Stop

    # Generate a certificate signing request in the Key Vault
    # -------------------------------------------------------
    Add-LogMessage -Level Info "Generating a certificate signing request for $($baseFqdn) to be signed by Let's Encrypt..."
    $SubjectName = "CN=$($baseFqdn),OU=$($config.shm.name),O=$($config.shm.organisation.name),L=$($config.shm.organisation.townCity),S=$($config.shm.organisation.stateCountyRegion),C=$($config.shm.organisation.countryCode)"
    $manualPolicy = New-AzKeyVaultCertificatePolicy -ValidityInMonths 3 -IssuerName "Unknown" -SubjectName "$SubjectName" -DnsName "$rdsFqdn"
    $manualPolicy.Exportable = $true
    $certificateOperation = Add-AzKeyVaultCertificate -VaultName $config.sre.keyVault.name -Name $certificateName -CertificatePolicy $manualPolicy
    $success = $?
    $csrPath = (New-TemporaryFile).FullName + ".csr"
    "-----BEGIN CERTIFICATE REQUEST-----`n" + $certificateOperation.CertificateSigningRequest + "`n-----END CERTIFICATE REQUEST-----" | Out-File -FilePath $csrPath
    if ($success) {
        Add-LogMessage -Level Success "CSR creation succeeded"
    } else {
        Add-LogMessage -Level Fatal "CSR creation failed!"
    }

    # Run Posh-ACME commands in a subjob to avoid incompatibility with the Az module
    # ------------------------------------------------------------------------------
    $certificateFilePath = Start-Job -ArgumentList @($PSScriptRoot, $token, $azureContext.Subscription.Id, $baseFqdn, $csrPath, $emailAddress, $dryRun) -ScriptBlock {
        param(
            [string]$ScriptRoot,
            [string]$AZAccessToken,
            [string]$AZSubscriptionId,
            [string]$BaseFqdn,
            [string]$CsrPath,
            [string]$EmailAddress,
            [bool]$dryRun
        )

        # Ensure that Posh-ACME is installed for current user
        # ---------------------------------------------------
        if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
            Install-Module -Name Posh-ACME -Scope CurrentUser -Force
        }
        Import-Module Posh-ACME -Force -ErrorAction Stop
        Import-Module $ScriptRoot/../../common/Logging -ErrorAction Stop


        # Set the Posh-ACME server to the appropriate Let's Encrypt endpoint
        # ------------------------------------------------------------------
        if ($dryRun) {
            Add-LogMessage -Level Info "Using Let's Encrypt staging server (dry-run)"
            $null = Set-PAServer LE_STAGE
        } else {
            Add-LogMessage -Level Info "Using Let's Encrypt production server!"
            $null = Set-PAServer LE_PROD
        }

        # Set Posh-ACME account
        # ---------------------
        Add-LogMessage -Level Info "[ ] Checking for Posh-ACME account"
        if (-not (Get-PAAccount -List -Contact $EmailAddress)) {
            $null = New-PAAccount -Contact $EmailAddress -AcceptTOS
            Add-LogMessage -Level Success "Created new Posh-ACME account for email address '$EmailAddress'"
        }
        $PoshAcmeAccount = Get-PAAccount -List -Contact $EmailAddress
        Add-LogMessage -Level Success "Using Posh-ACME account: $($PoshAcmeAccount.Id)"

        # Set Posh-ACME parameters
        # ------------------------
        $PoshAcmeParams = @{
            AZSubscriptionId = $AZSubscriptionId
            AZAccessToken    = $AZAccessToken
        }

        # Get the names for the publish and unpublish commands
        # ----------------------------------------------------
        $PublishCommandName = Get-Command -Module Posh-ACME -Name "Publish-*Challenge" | ForEach-Object { $_.Name }
        $UnpublishCommandName = Get-Command -Module Posh-ACME -Name "Unpublish-*Challenge" | ForEach-Object { $_.Name }

        # Test DNS record creation
        # ------------------------
        Add-LogMessage -Level Info "Test that we can interact with DNS records..."
        $testDomain = "dnstest.${BaseFqdn}"
        Add-LogMessage -Level Info "[ ] Attempting to create a DNS record for $testDomain..."
        if ($PublishCommandName -eq "Publish-DnsChallenge") {
            Add-LogMessage -Level Warning "The version of the Posh-ACME module that you are using is <4.0.0. Support for this version will be dropped in future."
            $null = Publish-DnsChallenge $testDomain -Account $PoshAcmeAccount -Token faketoken -Plugin Azure -PluginArgs $PoshAcmeParams -Verbose
        } else {
            $null = Publish-Challenge $testDomain -Account $PoshAcmeAccount -Token faketoken -Plugin Azure -PluginArgs $PoshAcmeParams -Verbose
        }
        if ($?) {
            Add-LogMessage -Level Success "DNS record creation succeeded"
        } else {
            Add-LogMessage -Level Fatal "DNS record creation failed!"
        }
        Add-LogMessage -Level Info "[ ] Attempting to delete a DNS record for $testDomain..."
        if ($UnpublishCommandName -eq "Unpublish-DnsChallenge") {
            Add-LogMessage -Level Warning "The version of the Posh-ACME module that you are using is <4.0.0. Support for this version will be dropped in future."
            $null = Unpublish-DnsChallenge $testDomain -Account $PoshAcmeAccount -Token faketoken -Plugin Azure -PluginArgs $PoshAcmeParams -Verbose
        } else {
            $null = Unpublish-Challenge $testDomain -Account $PoshAcmeAccount -Token faketoken -Plugin Azure -PluginArgs $PoshAcmeParams -Verbose
        }
        if ($?) {
            Add-LogMessage -Level Success "DNS record deletion succeeded"
        } else {
            Add-LogMessage -Level Fatal "DNS record deletion failed!"
        }

        # Send a certificate-signing-request to be signed
        # -----------------------------------------------
        Add-LogMessage -Level Info "Sending the CSR to be signed by Let's Encrypt..."
        if ($PublishCommandName -eq "Publish-DnsChallenge") {
            Add-LogMessage -Level Warning "The version of the Posh-ACME module that you are using is <4.0.0. Support for this version will be dropped in future."
            $null = Publish-DnsChallenge $BaseFqdn -Account $PoshAcmeAccount -Token faketoken -Plugin Azure -PluginArgs $PoshAcmeParams -Verbose
        } else {
            $null = Publish-Challenge $BaseFqdn -Account $PoshAcmeAccount -Token faketoken -Plugin Azure -PluginArgs $PoshAcmeParams -Verbose
        }
        $success = $?
        Add-LogMessage -Level Info "[ ] Creating certificate for ${BaseFqdn}..."
        $null = New-PACertificate -CSRPath $CsrPath -AcceptTOS -Contact $EmailAddress -DnsPlugin Azure -PluginArgs $PoshAcmeParams -Verbose
        $success = $success -and $?
        if ($success) {
            Add-LogMessage -Level Success "Certificate creation succeeded"
        } else {
            Add-LogMessage -Level Fatal "Certificate creation failed!"
        }
        return [string](Get-PACertificate -MainDomain $BaseFqdn).CertFile
    } | Receive-Job -Wait -AutoRemoveJob


    # Import signed certificate
    # -------------------------
    Add-LogMessage -Level Info "Importing signed certificate into Key Vault '$($config.sre.keyVault.name)'..."
    $kvCertificate = Import-AzKeyVaultCertificate -VaultName $config.sre.keyVault.name -Name $certificateName -FilePath $certificateFilePath
    if ($?) {
        Add-LogMessage -Level Success "Certificate import succeeded"
    } else {
        Add-LogMessage -Level Fatal "Certificate import failed!"
    }
}


# Warn if this is a dry run
# -------------------------
$doInstall = $true
if ($dryRun) {
    if ($forceInstall) {
        Add-LogMessage -Level Warning "Dry run produces an unsigned certificate! Forcing installation on the gateway anyway!"
    } else {
        Add-LogMessage -Level Error "Dry run produces an unsigned certificate! Use '-forceInstall' if you want to install this on the gateway anyway"
        $doInstall = $false
    }
}


# Install the certificate on the remote desktop gateway
# -----------------------------------------------------
if ($doInstall) {
    $vaultId = (Get-AzKeyVault -VaultName $config.sre.keyVault.name -ResourceGroupName $config.sre.keyVault.rg).ResourceId
    $secretURL = (Get-AzKeyVaultSecret -VaultName $config.sre.keyVault.name -Name $certificateName).Id

    if (1 -eq [int]$config.sre.tier) {

        # Add signed Key Vault certificate to the compute VM
        # --------------------------------------------------
        Add-LogMessage -Level Info "Adding SSL certificate to compute VM"
        $targetVM = Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | Select-Object -First 1 | Remove-AzVMSecret
        $targetVM = Add-AzVMSecret -VM $targetVM -SourceVaultId $vaultId -CertificateUrl $secretURL
        $null = Update-AzVM -ResourceGroupName $config.sre.dsvm.rg -VM $targetVM
        if ($?) {
            Add-LogMessage -Level Success "Adding certificate with thumbprint $($kvCertificate.Thumbprint) succeeded"
        } else {
            Add-LogMessage -Level Fatal "Adding certificate with thumbprint $($kvCertificate.Thumbprint) failed!"
        }

        # Link the certificate and private key to /opt/ssl
        # ------------------------------------------------
        $script = "
            sudo mkdir -p /opt/ssl
            sudo chmod 0700 /opt/ssl
            sudo rm -rf /opt/ssl/letsencrypt*
            sudo cp /var/lib/waagent/$($kvCertificate.Thumbprint).crt /opt/ssl/letsencrypt.cert
            sudo cp /var/lib/waagent/$($kvCertificate.Thumbprint).prv /opt/ssl/letsencrypt.key
            sudo chown -R root:root /opt/ssl/
            sudo chmod 0600 /opt/ssl/*.*
            ls -alh /opt/ssl/
        "
        $null = Invoke-RemoteScript -Shell "UnixShell" -Script $script -VMName $targetVM.Name -ResourceGroupName $config.sre.dsvm.rg

    } elseif (@(2, 3, 4).Contains([int]$config.sre.tier)) {

        # Add signed Key Vault certificate to the gateway VM
        # --------------------------------------------------
        Add-LogMessage -Level Info "Adding SSL certificate to RDS Gateway VM"
        $targetVM = Get-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName | Remove-AzVMSecret
        $targetVM = Add-AzVMSecret -VM $targetVM -SourceVaultId $vaultId -CertificateStore "My" -CertificateUrl $secretURL
        $null = Update-AzVM -ResourceGroupName $config.sre.rds.rg -VM $targetVM
        if ($?) {
            Add-LogMessage -Level Success "Adding certificate succeeded"
        } else {
            Add-LogMessage -Level Fatal "Adding certificate failed!"
        }

        # Configure RDS Gateway VM to use signed certificate
        # --------------------------------------------------
        Add-LogMessage -Level Info "Configuring RDS Gateway VM to use SSL certificate"
        $params = @{
            rdsFqdn         = $rdsFqdn
            certThumbPrint  = $kvCertificate.Thumbprint
            remoteDirectory = $remoteDirectory
        }
        $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Install_Signed_Ssl_Cert.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
