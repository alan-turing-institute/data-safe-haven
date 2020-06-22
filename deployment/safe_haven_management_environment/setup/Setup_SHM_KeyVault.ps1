param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Create secrets resource group if it does not exist
# --------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.keyVault.rg -Location $config.location


# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------
$null = Deploy-KeyVault -Name $config.keyVault.name -ResourceGroupName $config.keyVault.rg -Location $config.location
Set-KeyVaultPermissions -Name $config.keyVault.name -GroupName $config.adminSecurityGroupName


# Ensure that secrets exist in the keyvault
# -----------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.keyVault.name)'..."

# :: Admin usernames
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.domainAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()
    Add-LogMessage -Level Success "Ensured that SHM admin usernames exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SHM admin usernames exist!"
}
# :: AAD admin passwords
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadAdminPassword -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadLocalSyncPassword -DefaultLength 20
    Add-LogMessage -Level Success "Ensured that AAD admin passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that AAD admin passwords exist!"
}
# :: VM admin passwords
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.domainAdminPassword -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.dc.safemodePasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.nps.adminPasswordSecretName -DefaultLength 20
    foreach ($mirrorType in $config.mirrors.Keys) {
        foreach ($mirrorTier in $config.mirrors[$mirrorType].Keys) {
            foreach ($mirrorDirection in $config.mirrors[$mirrorType][$mirrorTier].Keys) {
                $adminPasswordSecretName = $config.mirrors[$mirrorType][$mirrorTier][$mirrorDirection].adminPasswordSecretName
                if ($adminPasswordSecretName) { $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $adminPasswordSecretName -DefaultLength 20 }
            }
        }
    }
    Add-LogMessage -Level Success "Ensured that SHM VM admin passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SHM VM admin passwords exist!"
}

# Ensure that certificates exist
# ------------------------------
try {
    # Define single folder for certificate generation for easier cleanup
    $certFolderPath = (New-Item -ItemType "directory" -Path "$((New-TemporaryFile).FullName).certificates").FullName

    # Certificate validities
    $caValidityDays = 825 # The CAB standard now limits certificates to 825 days
    $clientValidityDays = 732 # 2 years

    # Certificate local paths
    $caStem = "SHM-$($config.id)-P2S-CA".ToUpper()
    $caCrtPath = Join-Path $certFolderPath "$caStem.crt"
    $caKeyPath = Join-Path $certFolderPath "$caStem.key"
    $caPfxPath = Join-Path $certFolderPath "$caStem.pfx"
    $clientStem = "SHM-$($config.id)-P2S-CLIENT".ToUpper()
    $clientCrtPath = Join-Path $certFolderPath "$clientStem.crt"
    $clientCsrPath = Join-Path $certFolderPath "$clientStem.csr"
    # $clientKeyPath = Join-Path $certFolderPath "$clientStem.key"
    # $clientPfxPath = Join-Path $certFolderPath "$clientStem.pfx"
    $clientPkcs7Path = Join-Path $certFolderPath "$clientStem.p7b"

    # Generate or retrieve CA certificate
    # -----------------------------------
    Add-LogMessage -Level Info "Ensuring that self-signed CA certificate exists in the '$($config.keyVault.name)' KeyVault..."
    $vpnCaCertificate = (Get-AzKeyVaultCertificate -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificate).Certificate
    $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
    if ($vpnCaCertificate -And $vpnCaCertificatePlain) {
        Add-LogMessage -Level InfoSuccess "Found existing CA certificate"
    } else {
        # Remove any previous certificate with the same name
        # --------------------------------------------------
        Add-LogMessage -Level Info "Creating new self-signed CA certificate..."
        Remove-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate -Force -ErrorAction SilentlyContinue

        # Create self-signed CA certificate with private key
        # --------------------------------------------------
        Add-LogMessage -Level Info "[ ] Generating self-signed certificate locally"
        $vpnCaCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnCaCertPassword -DefaultLength 20
        openssl req -subj "/CN=$caStem" -new -newkey rsa:2048 -sha256 -days $caValidityDays -nodes -x509 -keyout $caKeyPath -out $caCrtPath
        openssl pkcs12 -in $caCrtPath -inkey $caKeyPath -export -out $caPfxPath -password "pass:$vpnCaCertPassword"
        if ($?) {
            Add-LogMessage -Level Success "Generating self-signed certificate succeeded"
        } else {
            Add-LogMessage -Level Fatal "Generating self-signed certificate failed!"
        }

        # Upload the CA key + cert bundle to the KeyVault
        # -----------------------------------------------
        Add-LogMessage -Level Info "[ ] Uploading CA private key + certificate bundle as certificate $($config.keyVault.secretNames.vpnCaCertificate) (includes private key)"
        $null = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnCaCertificate -FilePath $caPfxPath -Password (ConvertTo-SecureString $vpnCaCertPassword -AsPlainText -Force);
        if ($?) {
            Add-LogMessage -Level Success "Uploading the full CA certificate succeeded"
        } else {
            Add-LogMessage -Level Fatal "Uploading the full CA certificate failed!"
        }

        # # NB. this is not working at present - OSX reports that the CA certificate "is not standards compliant"
        # # Generate a self-signed CA certificate in the KeyVault
        # # -----------------------------------------------------
        # Add-LogMessage -Level Info "[ ] Generating self-signed certificate in the '$($config.keyVault.name)' KeyVault"
        # $caPolicy = New-AzKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -KeyType "RSA" -KeySize 2048 `
        #                                             -SubjectName "CN=$caStem" -ValidityInMonths $caValidityMonths -IssuerName "Self"
        # $caPolicy.Exportable = $true
        # $certificateOperation = Add-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate -CertificatePolicy $caPolicy
        # while ($status -ne "completed") {
        #     $status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).Status
        #     $progress = [math]::min(100, $progress + 9)
        #     Write-Progress -Activity "Certificate creation:" -Status $status -PercentComplete $progress
        #     Start-Sleep 1
        # }
        # if ($?) {
        #     Add-LogMessage -Level Success "Generating self-signed certificate succeeded"
        # } else {
        #     Add-LogMessage -Level Fatal "Generating self-signed certificate failed!"
        # }

        # Store plain CA certificate as a KeyVault secret
        # -----------------------------------------------
        Add-LogMessage -Level Info "[ ] Uploading the plain CA certificate as secret $($config.keyVault.secretNames.vpnCaCertificatePlain) (without private key)"
        $vpnCaCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).Certificate
        # Extract the public certificate and encode it as a Base64 string, without the header and footer lines and with a space every 64 characters
        $vpnCaCertificateB64String = [System.Convert]::ToBase64String($vpnCaCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        $vpnCaCertificatePlain = ($vpnCaCertificateB64String -split '(.{64})' | Where-Object { $_ }) -join " "
        $null = Set-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain -SecretValue (ConvertTo-SecureString "$vpnCaCertificatePlain" -AsPlainText -Force)
        if ($?) {
            Add-LogMessage -Level Success "Uploading the plain CA certificate succeeded"
        } else {
            Add-LogMessage -Level Fatal "Uploading the plain CA certificate failed!"
        }
    }

    # Generate or retrieve client certificate
    # ---------------------------------------
    Add-LogMessage -Level Info "Ensuring that client certificate exists in the '$($config.keyVault.name)' KeyVault..."
    $vpnClientCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate).Certificate
    if ($vpnClientCertificate) {
        Add-LogMessage -Level InfoSuccess "Found existing client certificate"
    } else {
        # Remove any previous certificate with the same name
        # --------------------------------------------------
        Add-LogMessage -Level Info "Creating new client certificate..."
        Remove-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate -Force -ErrorAction SilentlyContinue

        # Load CA certificate into local PFX file and extract the private key
        # -------------------------------------------------------------------
        Add-LogMessage -Level Info "[ ] Loading CA private key from key vault..."
        $caPfxBase64 = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).SecretValueText
        [IO.File]::WriteAllBytes($caPfxPath, [System.Convert]::FromBase64String($caPfxBase64))
        $caKeyData = openssl pkcs12 -in $caPfxPath -nocerts -nodes -passin pass:
        $caKeyData.Where({ $_ -like "-----BEGIN PRIVATE KEY-----" }, 'SkipUntil') | Out-File -FilePath $caKeyPath
        $caKeyMD5 = openssl rsa -noout -modulus -in $caKeyPath | openssl md5
        if ($?) {
            Add-LogMessage -Level Success "Loading CA private key succeeded"
        } else {
            Add-LogMessage -Level Fatal "Loading CA private key failed!"
        }

        # Split CA certificate into key and certificate
        # ---------------------------------------------
        Add-LogMessage -Level Info "[ ] Retrieving CA plain certificate..."
        # Write CA certificate to a file after stripping headers and reflowing to a maximum of 64 characters per line
        $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
        "-----BEGIN CERTIFICATE-----" | Out-File -FilePath $caCrtPath
        $vpnCaCertificatePlain.Replace(" ", "") -split '(.{64})' | Where-Object { $_ } | Out-File -Append -FilePath $caCrtPath
        "-----END CERTIFICATE-----" | Out-File -Append -FilePath $caCrtPath
        $caCrtMD5 = openssl x509 -noout -modulus -in $caCrtPath | openssl md5
        if ($caKeyMD5 -eq $caCrtMD5) {
            Add-LogMessage -Level Success "Validated CA certificate retrieval using MD5"
        } else {
            Add-LogMessage -Level Fatal "Failed to validate CA certificate retrieval using MD5!"
        }

        # Generate a CSR in the KeyVault
        # ------------------------------
        Add-LogMessage -Level Info "[ ] Creating new certificate signing request to be signed by the CA certificate..."
        if ($status -ne "inProgress") {
            $clientPolicy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=$clientStem" -ValidityInMonths $clientValidityMonths -IssuerName "Unknown"
            $null = Add-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate -CertificatePolicy $clientPolicy
        }
        $certificateOperation = Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate
        $success = $?
        # Write the CSR after reflowing to a maximum of 64 characters per line
        "-----BEGIN CERTIFICATE REQUEST-----" | Out-File -FilePath $clientCsrPath
        $certificateOperation.CertificateSigningRequest -split '(.{64})' | Where-Object { $_ } | Out-File -Append -FilePath $clientCsrPath
        "-----END CERTIFICATE REQUEST-----" | Out-File -Append -FilePath $clientCsrPath
        if ($success) {
            Add-LogMessage -Level Success "CSR creation succeeded"
        } else {
            Add-LogMessage -Level Fatal "CSR creation failed!"
        }

        # Sign the client certificate - create a PKCS#7 file from full certificate chain and merge it with the private key
        # ----------------------------------------------------------------------------------------------------------------
        Add-LogMessage -Level Info "[ ] Signing the CSR and merging into the '$($config.keyVault.secretNames.vpnClientCertificate)' certificate..."
        $vpnClientCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnClientCertPassword -DefaultLength 20
        openssl x509 -req -in $clientCsrPath -CA $caCrtPath -CAkey $caKeyPath -CAcreateserial -out $clientCrtPath -days $clientValidityDays -sha256
        openssl crl2pkcs7 -nocrl -certfile $clientCrtPath -certfile $caCrtPath -out $clientPkcs7Path 2>&1 | Out-Null
        $null = Import-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate -FilePath $clientPkcs7Path -Password (ConvertTo-SecureString "$vpnClientCertPassword" -AsPlainText -Force)
        if ($?) {
            Add-LogMessage -Level Success "Importing the signed client certificate succeeded"
        } else {
            Add-LogMessage -Level Fatal "Importing the signed client certificate failed!"
        }
    }
} finally {
    # Delete local copies of certificates and private keys
    Get-ChildItem $certFolderPath -Recurse | Remove-Item -Recurse
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
