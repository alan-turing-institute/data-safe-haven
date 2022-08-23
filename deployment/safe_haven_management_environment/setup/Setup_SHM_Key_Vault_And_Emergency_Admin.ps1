param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Cryptography -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Connect to Microsoft Graph
# --------------------------
if (Get-MgContext) { Disconnect-MgGraph } # force a refresh of the Microsoft Graph token before starting
Add-LogMessage -Level Info "Authenticating against Azure Active Directory: use an AAD global administrator for tenant ($tenantId)..."
Connect-MgGraph -TenantId $tenantId -Scopes "User.ReadWrite.All", "UserAuthenticationMethod.ReadWrite.All", "Directory.AccessAsUser.All", "RoleManagement.ReadWrite.Directory" -ErrorAction Stop
if (Get-MgContext) {
    Add-LogMessage -Level Success "Authenticated with Microsoft Graph"
} else {
    Add-LogMessage -Level Fatal "Failed to authenticate with Microsoft Graph"
}


# Create secrets resource group if it does not exist
# --------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.keyVault.rg -Location $config.location


# Ensure the Key Vault exists and set its access policies
# -------------------------------------------------------
$null = Deploy-KeyVault -Name $config.keyVault.name -ResourceGroupName $config.keyVault.rg -Location $config.location
Set-KeyVaultPermissions -Name $config.keyVault.name -GroupName $config.azureAdminGroupName


# Ensure that secrets exist in the Key Vault
# ------------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in Key Vault '$($config.keyVault.name)'..."

# :: AAD Emergency Administrator username
$null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.aadEmergencyAdminUsername -DefaultValue "aad.admin.emergency.access" -AsPlaintext
if ($?) {
    Add-LogMessage -Level Success "AAD emergency administrator account username exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create AAD Emergency Global Administrator username!"
}

# :: AAD Emergency Administrator password
$null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadEmergencyAdminPassword -DefaultLength 20 -AsPlaintext
if ($?) {
    Add-LogMessage -Level Success "AAD emergency administrator account password exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create AAD Emergency Global Administrator password!"
}

# :: Admin usernames
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.domainAdminUsername -DefaultValue "domain$($config.id)admin".ToLower() -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower() -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.users.serviceAccounts.aadLocalSync.usernameSecretName -DefaultValue $config.users.serviceAccounts.aadLocalSync.samAccountName -AsPlaintext
    Add-LogMessage -Level Success "Ensured that SHM admin usernames exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SHM admin usernames exist!" -Exception $_.Exception
}
# :: VM admin passwords
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.domainAdminPassword -DefaultLength 20 -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.dc.safemodePasswordSecretName -DefaultLength 20 -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.nps.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.updateServers.linux.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    foreach ($repositoryTier in $config.repository.Keys) {
        $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.repository[$repositoryTier].nexus.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    }
    foreach ($mirrorType in $config.mirrors.Keys) {
        foreach ($mirrorTier in $config.mirrors[$mirrorType].Keys) {
            foreach ($mirrorDirection in $config.mirrors[$mirrorType][$mirrorTier].Keys) {
                $adminPasswordSecretName = $config.mirrors[$mirrorType][$mirrorTier][$mirrorDirection].adminPasswordSecretName
                if ($adminPasswordSecretName) { $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $adminPasswordSecretName -DefaultLength 20 -AsPlaintext }
            }
        }
    }
    Add-LogMessage -Level Success "Ensured that SHM VM admin passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SHM VM admin passwords exist!" -Exception $_.Exception
}
# :: Computer manager users
try {
    $computerManagers = $config.users.computerManagers
    foreach ($user in $computerManagers.Keys) {
        $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $computerManagers[$user]["passwordSecretName"] -DefaultLength 20 -AsPlaintext
    }
    Add-LogMessage -Level Success "Ensured that domain joining passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that domain joining passwords exist!" -Exception $_.Exception
}
# :: Service accounts
try {
    $serviceAccounts = $config.users.serviceAccounts
    foreach ($user in $serviceAccounts.Keys) {
        $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $serviceAccounts[$user]["passwordSecretName"] -DefaultLength 20 -AsPlaintext
    }
    Add-LogMessage -Level Success "Ensured that service account passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that service account passwords exist!" -Exception $_.Exception
}


# Set Emergency Admin user properties
# -----------------------------------
$username = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadEmergencyAdminUsername -AsPlaintext
$userPrincipalName = "$username@$($config.domain.fqdn)"
$params = @{
    MailNickName     = $username
    DisplayName      = "AAD Admin - EMERGENCY ACCESS"
    PasswordProfile  = @{
        Password                             = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadEmergencyAdminPassword -AsPlaintext
        ForceChangePasswordNextSignInWithMfa = $false
        ForceChangePasswordNextSignIn        = $false
    }
    UserType         = "Member"
    AccountEnabled   = $true
    PasswordPolicies = "DisablePasswordExpiration"
    UsageLocation    = $config.organisation.countryCode
}


# Ensure emergency admin user exists
# ----------------------------------
Add-LogMessage -Level Info "Ensuring AAD emergency administrator account exists..."
$globalAdminUser = Get-MgUser | Where-Object { $_.UserPrincipalName -eq $userPrincipalName }
if ($globalAdminUser) {
    # Update existing user
    $globalAdminUser = Update-MgUser -UserId $globalAdminUser.Id @params
    if ($?) {
        Add-LogMessage -Level Success "Existing AAD emergency administrator account updated."
    } else {
        Add-LogMessage -Level Fatal "Failed to update existing AAD emergency administrator account!"
    }
} else {
    # Create new user
    $globalAdminUser = New-MgUser -UserPrincipalName $userPrincipalName @params
    if ($?) {
        Add-LogMessage -Level Success "AAD emergency administrator account created."
    } else {
        Add-LogMessage -Level Fatal "Failed to create AAD emergency administrator account!"
    }
}

# Ensure emergency admin account has full administrator rights
# ------------------------------------------------------------
$globalAdminRoleName = "Global Administrator"
Add-LogMessage -Level Info "Ensuring AAD emergency administrator has '$globalAdminRoleName' role..."
$globalAdminRole = Get-MgDirectoryRole | Where-Object { $_.DisplayName -eq $globalAdminRoleName }
# If role instance does not exist, instantiate it based on the role template
if ($null -eq $globalAdminRole) {
    Add-LogMessage -Level Info "'$globalAdminRoleName' does not exist. Creating role from template..."
    # Instantiate an instance of the role template
    $globalAdminRoleTemplate = Get-MgDirectoryRoleTemplate | Where-Object { $_.DisplayName -eq $globalAdminRoleName }
    New-MgDirectoryRole -RoleTemplateId $globalAdminRoleTemplate.Id
    if ($?) {
        Add-LogMessage -Level Success "'$globalAdminRoleName' created from template."
    } else {
        Add-LogMessage -Level Fatal "Failed to create '$globalAdminRoleName' from template!"
    }
    # Fetch role instance again
    $globalAdminRole = Get-MgDirectoryRole | Where-Object { $_.DisplayName -eq $globalAdminRoleName }
}
# Ensure user is assigned to the role
$globalAdminUser = Get-MgUser | Where-Object { $_.UserPrincipalName -eq $userPrincipalName }
$userHasRole = Get-MgDirectoryRoleMember -DirectoryRoleId $globalAdminRole.Id | Where-Object { $_.Id -eq $globalAdminUser.Id }
if ($userHasRole) {
    Add-LogMessage -Level Success "AAD emergency administrator already has '$globalAdminRoleName' role."
} else {
    New-MgDirectoryRoleMemberByRef -DirectoryRoleId $globalAdminRole.Id -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($globalAdminUser.Id)" }
    $userHasRole = Get-MgDirectoryRoleMember -DirectoryRoleId $globalAdminRole.Id | Where-Object { $_.Id -eq $globalAdminUser.Id }
    if ($userHasRole) {
        Add-LogMessage -Level Success "Granted AAD emergency administrator '$globalAdminRoleName' role."
    } else {
        Add-LogMessage -Level Failure "Failed to grant AAD emergency administrator '$globalAdminRoleName' role!"
    }
}


# Sign out of Microsoft Graph
# ---------------------------
Disconnect-MgGraph


# Ensure that certificates exist
# ------------------------------
try {
    # Certificate validities
    $caValidityMonths = 27 # The CAB standard now limits certificates to 825 days
    $caValidityDays = (Get-Date | ForEach-Object { $_.AddMonths($caValidityMonths) - $_ }).Days
    $clientValidityMonths = 24 # 2 years
    $clientValidityDays = (Get-Date | ForEach-Object { $_.AddMonths($clientValidityMonths) - $_ }).Days

    # Generate all certificates in a single folder for easier cleanup
    $certFolderPath = (New-Item -ItemType "directory" -Path "$((New-TemporaryFile).FullName).certificates").FullName
    $caStem = "SHM-$($config.id)-P2S-CA".ToUpper()
    $caCrtPath = Join-Path $certFolderPath "${caStem}.crt"
    $caKeyPath = Join-Path $certFolderPath "${caStem}.key"
    $caPfxPath = Join-Path $certFolderPath "${caStem}.pfx"
    $clientStem = "SHM-$($config.id)-P2S-CLIENT".ToUpper()
    $clientCrtPath = Join-Path $certFolderPath "${clientStem}.crt"
    $clientCsrPath = Join-Path $certFolderPath "${clientStem}.csr"
    $clientPkcs7Path = Join-Path $certFolderPath "${clientStem}.p7b"

    # Ensure that CA certificate exists in the Key Vault
    # --------------------------------------------------
    Add-LogMessage -Level Info "Ensuring that self-signed CA certificate exists in the '$($config.keyVault.name)' Key Vault..."
    # Check whether a certificate with a valid private key already exists in the Key Vault. If not, then remove and purge any existing certificate with this name
    $newCertRequired = $True
    $existingCert = Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate
    if ($existingCert) {
        if ($existingCert.Certificate.HasPrivateKey) {
            Add-LogMessage -Level InfoSuccess "Found existing CA certificate"
            $newCertRequired = $False
        } else {
            Remove-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate -Force -ErrorAction SilentlyContinue
            Remove-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate -InRemovedState -Force -ErrorAction SilentlyContinue
        }
    }
    # Generate a new certificate if required
    if ($newCertRequired) {
        Add-LogMessage -Level Info "Creating new self-signed CA certificate..."

        # Create self-signed CA certificate with private key
        # --------------------------------------------------
        Add-LogMessage -Level Info "[ ] Generating self-signed certificate locally"
        $vpnCaCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnCaCertPassword -DefaultLength 20 -AsPlaintext
        openssl req -subj "/CN=$caStem" -new -newkey rsa:2048 -sha256 -days $caValidityDays -nodes -x509 -keyout $caKeyPath -out $caCrtPath
        openssl pkcs12 -in $caCrtPath -inkey $caKeyPath -export -out $caPfxPath -password "pass:$vpnCaCertPassword"
        if ($?) {
            Add-LogMessage -Level Success "Generating self-signed certificate succeeded"
        } else {
            Add-LogMessage -Level Fatal "Generating self-signed certificate failed!"
        }

        # Upload the CA key + cert bundle to the Key Vault
        # ------------------------------------------------
        Add-LogMessage -Level Info "[ ] Uploading CA private key + certificate bundle as certificate $($config.keyVault.secretNames.vpnCaCertificate) (includes private key)"
        $null = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnCaCertificate -FilePath $caPfxPath -Password (ConvertTo-SecureString $vpnCaCertPassword -AsPlainText -Force);
        if ($?) {
            Add-LogMessage -Level Success "Uploading the full CA certificate succeeded"
        } else {
            Add-LogMessage -Level Fatal "Uploading the full CA certificate failed!"
        }

        # # NB. this is not working at present - OSX reports that the CA certificate "is not standards compliant"
        # # Generate a self-signed CA certificate in the Key Vault
        # # ------------------------------------------------------
        # Add-LogMessage -Level Info "[ ] Generating self-signed certificate in the '$($config.keyVault.name)' Key Vault"
        # $caPolicy = New-AzKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -KeyType "RSA" -KeyUsage @("KeyCertSign", "CrlSign") -Ekus @("1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2", "2.5.29.37.0") -KeySize 2048 -SubjectName "CN=$caStem" -ValidityInMonths $caValidityMonths -IssuerName "Self"
        # $caPolicy.Exportable = $true
        # $certificateOperation = Add-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate -CertificatePolicy $caPolicy
        # while ($status -ne "completed") {
        #     $status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate).Status
        #     $progress = [math]::min(100, $progress + 9)
        #     Write-Progress -Activity "Certificate creation:" -Status $status -PercentComplete $progress
        #     Start-Sleep 1
        # }
        # if ($?) {
        #     Add-LogMessage -Level Success "Generating self-signed certificate succeeded"
        # } else {
        #     Add-LogMessage -Level Fatal "Generating self-signed certificate failed!"
        # }

        # Store plain CA certificate as a Key Vault secret
        # ------------------------------------------------
        Add-LogMessage -Level Info "[ ] Uploading the plain CA certificate as secret $($config.keyVault.secretNames.vpnCaCertificatePlain) (without private key)"
        $vpnCaCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate).Certificate
        # Extract the public certificate and encode it as a Base64 string, without the header and footer lines and with a space every 64 characters
        $vpnCaCertificateB64String = [System.Convert]::ToBase64String($vpnCaCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        $vpnCaCertificatePlain = ($vpnCaCertificateB64String -split '(.{64})' | Where-Object { $_ }) -join " "
        $null = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificatePlain -SecretValue (ConvertTo-SecureString "$vpnCaCertificatePlain" -AsPlainText -Force)
        if ($?) {
            Add-LogMessage -Level Success "Uploading the plain CA certificate succeeded"
        } else {
            Add-LogMessage -Level Fatal "Uploading the plain CA certificate failed!"
        }
    }

    # Generate or retrieve client certificate
    # ---------------------------------------
    Add-LogMessage -Level Info "Ensuring that client certificate exists in the '$($config.keyVault.name)' Key Vault..."
    # Check whether a certificate with a valid private key already exists in the Key Vault. If not, then remove and purge any existing certificate with this name
    $newCertRequired = $True
    $existingCert = Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate
    if ($existingCert) {
        if ($existingCert.Certificate.HasPrivateKey) {
            Add-LogMessage -Level InfoSuccess "Found existing client certificate"
            $newCertRequired = $False
        } else {
            Remove-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate -Force -ErrorAction SilentlyContinue
            Remove-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate -InRemovedState -Force -ErrorAction SilentlyContinue
        }
    }
    # Generate a new certificate if required
    if ($newCertRequired) {
        Add-LogMessage -Level Info "Creating new client certificate..."

        # Load CA certificate into local PFX file and extract the private key
        # -------------------------------------------------------------------
        Add-LogMessage -Level Info "[ ] Loading CA private key from Key Vault..."
        $caPfxBase64 = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnCaCertificate -AsPlaintext
        [IO.File]::WriteAllBytes($caPfxPath, [System.Convert]::FromBase64String($caPfxBase64))
        $caKeyData = openssl pkcs12 -in $caPfxPath -nocerts -nodes -passin pass:
        $caKeyData.Where( { $_ -like "-----BEGIN PRIVATE KEY-----" }, 'SkipUntil') | Out-File -FilePath $caKeyPath
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
        $vpnCaCertificatePlain = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnCaCertificatePlain -AsPlaintext
        "-----BEGIN CERTIFICATE-----" | Out-File -FilePath $caCrtPath
        $vpnCaCertificatePlain.Replace(" ", "") -split '(.{64})' | Where-Object { $_ } | Out-File -Append -FilePath $caCrtPath
        "-----END CERTIFICATE-----" | Out-File -Append -FilePath $caCrtPath
        $caCrtMD5 = openssl x509 -noout -modulus -in $caCrtPath | openssl md5
        if ($caKeyMD5 -eq $caCrtMD5) {
            Add-LogMessage -Level Success "Validated CA certificate retrieval using MD5"
        } else {
            Add-LogMessage -Level Fatal "Failed to validate CA certificate retrieval using MD5!"
        }

        # Generate a CSR in the Key Vault
        # -------------------------------
        Add-LogMessage -Level Info "[ ] Creating new certificate signing request to be signed by the CA certificate..."
        if ($status -ne "inProgress") {
            $clientPolicy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=$clientStem" -ValidityInMonths $clientValidityMonths -IssuerName "Unknown"
            $null = Add-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate -CertificatePolicy $clientPolicy
        }
        $certificateOperation = Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate
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
        $vpnClientCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnClientCertPassword -DefaultLength 20 -AsPlaintext
        openssl x509 -req -in $clientCsrPath -CA $caCrtPath -CAkey $caKeyPath -CAcreateserial -out $clientCrtPath -days $clientValidityDays -sha256
        openssl crl2pkcs7 -nocrl -certfile $clientCrtPath -certfile $caCrtPath -out $clientPkcs7Path 2>&1 | Out-Null
        $null = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate -FilePath $clientPkcs7Path -Password (ConvertTo-SecureString "$vpnClientCertPassword" -AsPlainText -Force)
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
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
