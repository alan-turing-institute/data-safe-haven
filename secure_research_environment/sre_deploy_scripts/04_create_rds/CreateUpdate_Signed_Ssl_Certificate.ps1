param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId,
    [Parameter(Position = 1,Mandatory = $false,HelpMessage = "Email address to associate with the certificate request.")]
    [string]$emailAddress = "dsgbuild@turing.ac.uk",
    [Parameter(Position = 2,Mandatory = $false,HelpMessage = "Do a 'dry run' against the Let's Encrypt staging server.")]
    [bool]$dryRun = $false,
    [Parameter(Position = 3,Mandatory = $false,HelpMessage = "Force the installation step even for dry runs.")]
    [bool]$forceInstall = $false,
    [Parameter(Position = 4,Mandatory = $false,HelpMessage = "Local directory (defaults to '~/Certificates')")]
    [string]$localDirectory = "$HOME/Certificates",
    [Parameter(Position = 5,Mandatory = $false,HelpMessage = "Remote directory (defaults to '/Certificates')")]
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
$config = Get-SreConfig ($sreId);
$originalContext = Get-AzContext


# Set common variables
# --------------------
$keyvaultName = $config.dsg.keyVault.Name
$certificateName = $config.dsg.keyVault.secretNames.letsEncryptCertificate
if ($dryRun) { $certificateName += "-dryrun" }


# Check for existing certificate in KeyVault
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Checking whether signed certificate '$certificateName' already exists in KeyVault..."
$kvCertificate = Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName
$requestCertificate = $false


# Determine whether a certificate request is needed
# -------------------------------------------------
if ($kvCertificate -eq $null) {
    Write-Host -ForegroundColor DarkCyan "No certificate found in KeyVault '$keyvaultName'"
    $requestCertificate = $true
} else {
    $renewalDate = [datetime]::ParseExact($kvCertificate.Certificate.NotAfter,"MM/dd/yyyy HH:mm:ss",$null).AddDays(-30)
    Write-Host -ForegroundColor DarkGreen " [o] Loaded certificate from KeyVault '$keyvaultName' with earliest renewal date $($renewalDate.ToString('dd MMM yyyy'))"
    if ($(Get-Date) -ge $renewalDate) {
        Write-Host -ForegroundColor DarkGreen "Removing outdated certificate from KeyVault '$keyvaultName'..."
        $_ = Remove-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName -Force
        $requestCertificate = $true
    }
}


# Request a new certificate
# -------------------------
if ($requestCertificate) {
    Write-Host -ForegroundColor DarkCyan "Preparing to request a new certificate..."

    # Set the Posh-ACME server to the appropriate Let's Encrypt endpoint
    # ------------------------------------------------------------------
    if ($dryRun) {
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
    $token = ($azureContext.TokenCache.ReadItems() | Where-Object { ($_.TenantId -eq $azureContext.Subscription.TenantId) -and ($_.Resource -eq "https://management.core.windows.net/") } | Select-Object -First 1).AccessToken
    $_ = Set-AzContext -Subscription $config.dsg.subscriptionName;

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


# Warn if this is a dry run
# -------------------------
$doInstall = $true
if ($dryRun) {
    if ($forceInstall) {
        Write-Host -ForegroundColor DarkCyan "Dry run produces an unsigned certificate! Forcing installation on the gateway anyway!"
    } else {
        Write-Host -ForegroundColor DarkCyan "Dry run produces an unsigned certificate! Use '-forceInstall `$true' if you want to install this on the gateway anyway"
        $doInstall = $false
    }
}


if ($doInstall) {
    # Add signed KeyVault certificate to the gateway VM
    # -------------------------------------------------
    Write-Host -ForegroundColor DarkCyan "Adding SSL certificate to RDS Gateway VM"
    $vaultId = (Get-AzKeyVault -ResourceGroupName $config.dsg.keyVault.rg -VaultName $keyVaultName).ResourceId
    $secretURL = (Get-AzKeyVaultSecret -VaultName $keyvaultName -Name $certificateName).Id
    $gatewayVm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName | Remove-AzVMSecret
    $gatewayVm = Add-AzVMSecret -VM $gatewayVm -SourceVaultId $vaultId -CertificateStore "My" -CertificateUrl $secretURL
    $_ = Update-AzVM -ResourceGroupName $config.dsg.rds.rg -VM $gatewayVm
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] Adding certificate succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Adding certificate failed!"
        throw "Unable to add certificate to $($config.dsg.rds.gateway.vmName)!"
    }

    # Configure RDS Gateway VM to use signed certificate
    # --------------------------------------------------
    Write-Host -ForegroundColor DarkCyan "Configuring RDS Gateway VM to use SSL certificate"
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
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
