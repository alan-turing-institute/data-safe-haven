param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId,
    [Parameter(Position = 1, Mandatory = $false, HelpMessage = "Email address to associate with the certificate request.")]
    [string]$emailAddress = "dsgbuild@turing.ac.uk",
    [Parameter(Position = 2, Mandatory = $false, HelpMessage = "Do a 'dry run' against the Let's Encrypt staging server.")]
    [bool]$dryRun = $false,
    [Parameter(Position = 3, Mandatory = $false, HelpMessage = "Force the installation step even for dry runs.")]
    [bool]$forceInstall = $false,
    [Parameter(Position = 4, Mandatory = $false, HelpMessage = "Local directory (defaults to '~/Certificates')")]
    [string]$localDirectory = "$HOME/Certificates",
    [Parameter(Position = 5, Mandatory = $false, HelpMessage = "Remote directory (defaults to '/Certificates')")]
    [string]$remoteDirectory = "/Certificates"
)

# Ensure that Posh-ACME is installed for current user
if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
    Install-Module -Name Posh-ACME -Scope CurrentUser -Force
}

# Import modules
Import-Module Posh-ACME
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context
# -------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -Subscription $config.sre.subscriptionName


# Set common variables
# --------------------
$keyVaultName = $config.sre.keyVault.Name
$certificateName = $config.sre.keyVault.secretNames.letsEncryptCertificate
if ($dryRun) { $certificateName += "-dryrun" }


# Check for existing certificate in KeyVault
# ------------------------------------------
Add-LogMessage -Level Info "[ ] Checking whether signed certificate '$certificateName' already exists in key vault..."
$kvCertificate = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName
$requestCertificate = $false


# Determine whether a certificate request is needed
# -------------------------------------------------
if ($null -eq $kvCertificate) {
    Add-LogMessage -Level Info "No certificate found in key vault '$keyVaultName'"
    $requestCertificate = $true
} else {
    try {
        $renewalDate = [datetime]::ParseExact($kvCertificate.Certificate.NotAfter, "MM/dd/yyyy HH:mm:ss", $null).AddDays(-30)
        Add-LogMessage -Level Success "Loaded certificate from key vault '$keyVaultName' with earliest renewal date $($renewalDate.ToString('dd MMM yyyy'))"
    } catch [System.Management.Automation.MethodInvocationException] {
        $renewalDate = $null
    }
    if (($null -eq $renewalDate) -or ($(Get-Date) -ge $renewalDate)) {
        Add-LogMessage -Level Warning "Removing outdated certificate from KeyVault '$keyVaultName'..."
        $_ = Remove-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -Force
        $requestCertificate = $true
    }
}


# Request a new certificate
# -------------------------
if ($requestCertificate) {
    Add-LogMessage -Level Info "Preparing to request a new certificate..."
    $baseFqdn = $config.sre.domain.fqdn
    $rdsFqdn = $config.sre.rds.gateway.fqdn

    # Set the Posh-ACME server to the appropriate Let's Encrypt endpoint
    # ------------------------------------------------------------------
    if ($dryRun) {
        Add-LogMessage -Level Info "Using Let's Encrypt staging server (dry-run)"
        Set-PAServer LE_STAGE
    } else {
        Add-LogMessage -Level Info "Using Let's Encrypt production server!"
        Set-PAServer LE_PROD
    }

    # Set Posh-ACME account
    # --------------
    Add-LogMessage -Level Info "[ ] Checking for Posh-ACME account"
    $acct = Get-PAAccount -List -Contact $emailAddress
    if ($null -eq $acct) {
        $account = New-PAAccount -Contact $emailAddress -AcceptTOS
        Add-LogMessage -Level Success "Created new Posh-ACME account with ID: '$($account.id)'"
        $acct = Get-PAAccount -List -Contact $emailAddress
    }
    Add-LogMessage -Level Success "Using Posh-ACME account: $($acct.id)"

    # Get token for DNS subscription
    # ------------------------------
    $azureContext = Set-AzContext -Subscription $config.shm.dns.subscriptionName
    $token = ($azureContext.TokenCache.ReadItems() | Where-Object { ($_.TenantId -eq $azureContext.Subscription.TenantId) -and ($_.Resource -eq "https://management.core.windows.net/") } | Select-Object -First 1).AccessToken
    $_ = Set-AzContext -Subscription $config.sre.subscriptionName

    # Test DNS record creation
    # ------------------------
    Add-LogMessage -Level Info "Test that we can interact with DNS records..."
    $testDomain = "dnstest.$($baseFqdn)"
    $params = @{
        AZSubscriptionId = $azureContext.Subscription.Id
        AZAccessToken = $token
    }
    Add-LogMessage -Level Info "[ ] Attempting to create a DNS record for $testDomain..."
    Publish-DnsChallenge $testDomain -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
    if ($?) {
        Add-LogMessage -Level Success "DNS record creation succeeded"
    } else {
        Add-LogMessage -Level Fatal "DNS record creation failed!"
    }
    Add-LogMessage -Level Info " [ ] Attempting to delete a DNS record for $testDomain..."
    Unpublish-DnsChallenge $testDomain -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
    if ($?) {
        Add-LogMessage -Level Success "DNS record deletion succeeded"
    } else {
        Add-LogMessage -Level Fatal "DNS record deletion failed!"
    }


    # Generate a certificate signing request in the KeyVault
    # ------------------------------------------------------
    $csrPath = (New-TemporaryFile).FullName + ".csr"
    Add-LogMessage -Level Info "Generating a certificate signing request for $($baseFqdn) to be signed by Let's Encrypt..."
    $SubjectName = "CN=$($baseFqdn),OU=$($config.shm.name),O=$($config.shm.organisation.name),L=$($config.shm.organisation.townCity),S=$($config.shm.organisation.stateCountyRegion),C=$($config.shm.organisation.countryCode)"
    $manualPolicy = New-AzKeyVaultCertificatePolicy -ValidityInMonths 1 -IssuerName "Unknown" -SubjectName "$SubjectName" -DnsName "$rdsFqdn"
    $manualPolicy.Exportable = $true
    $certificateOperation = Add-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -CertificatePolicy $manualPolicy
    $success = $?
    "-----BEGIN CERTIFICATE REQUEST-----`n" + $certificateOperation.CertificateSigningRequest + "`n-----END CERTIFICATE REQUEST-----" | Out-File -FilePath $csrPath
    if ($success) {
        Add-LogMessage -Level Success "CSR creation succeeded"
    } else {
        Add-LogMessage -Level Fatal "CSR creation failed!"
    }

    # Send the certificate to be signed
    # ---------------------------------
    Add-LogMessage -Level Info "Sending the CSR to be signed by Let's Encrypt..."
    Publish-DnsChallenge $baseFqdn -Account $acct -Token faketoken -Plugin Azure -PluginArgs $params -Verbose
    Add-LogMessage -Level Info "[ ] Creating certificate for $($baseFqdn)..."
    New-PACertificate -CSRPath $csrPath -AcceptTOS -Contact $emailAddress -DnsPlugin Azure -PluginArgs $params -Verbose
    if ($?) {
        Add-LogMessage -Level Success "Certificate creation succeeded"
    } else {
        Add-LogMessage -Level Fatal "Certificate creation failed!"
    }
    $paCertificate = Get-PACertificate -MainDomain $baseFqdn

    # Import signed certificate
    # -------------------------
    Add-LogMessage -Level Info "Importing signed certificate into KeyVault '$keyVaultName'..."
    $kvCertificate = Import-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -FilePath $paCertificate.CertFile
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
        Add-LogMessage -Level Error "Dry run produces an unsigned certificate! Use '-forceInstall `$true' if you want to install this on the gateway anyway"
        $doInstall = $false
    }
}


if ($doInstall) {
    # Add signed KeyVault certificate to the gateway VM
    # -------------------------------------------------
    Add-LogMessage -Level Info "Adding SSL certificate to RDS Gateway VM"
    $vaultId = (Get-AzKeyVault -ResourceGroupName $config.sre.keyVault.rg -VaultName $keyVaultName).ResourceId
    $secretURL = (Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $certificateName).Id
    $gatewayVm = Get-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName | Remove-AzVMSecret
    $gatewayVm = Add-AzVMSecret -VM $gatewayVm -SourceVaultId $vaultId -CertificateStore "My" -CertificateUrl $secretURL
    $_ = Update-AzVM -ResourceGroupName $config.sre.rds.rg -VM $gatewayVm
    if ($?) {
        Add-LogMessage -Level Success "Adding certificate succeeded"
    } else {
        Add-LogMessage -Level Fatal "Adding certificate failed!"
    }

    # Configure RDS Gateway VM to use signed certificate
    # --------------------------------------------------
    Add-LogMessage -Level Info "Configuring RDS Gateway VM to use SSL certificate"
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Install_Signed_Ssl_Cert.ps1"
    $params = @{
        rdsFqdn = "`"$rdsFqdn`""
        certThumbPrint = "`"$($kvCertificate.Thumbprint)`""
        remoteDirectory = "`"$remoteDirectory`""
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
    Write-Output $result.Value
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
