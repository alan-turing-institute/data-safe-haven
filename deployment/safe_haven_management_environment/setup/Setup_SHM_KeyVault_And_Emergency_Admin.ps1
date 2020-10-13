param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId
)

# Connect to the Azure AD
# Note that this must be done in a fresh Powershell session with nothing else imported
# ------------------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name AzureAD.Standard.Preview)) {
    Write-Output "Installing Azure AD Powershell module..."
    $null = Register-PackageSource -Trusted -ProviderName "PowerShellGet" -Name "Posh Test Gallery" -Location https://www.poshtestgallery.com/api/v2/ -ErrorAction SilentlyContinue
    $null = Install-Module AzureAD.Standard.Preview -Repository "Posh Test Gallery" -Force
}
Import-Module AzureAD.Standard.Preview
Write-Output "Connecting to Azure AD '$tenantId'..."
try {
    $null = Connect-AzureAD -TenantId $tenantId
} catch {
    Write-Output "Please run this script in a fresh Powershell session with no other modules imported!"
    throw
}

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
Set-KeyVaultPermissions -Name $config.keyVault.name -GroupName $config.azureAdminGroupName


# Ensure that secrets exist in the keyvault
# -----------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.keyVault.name)'..."
$emergencyAdminUsername = "aad.admin.emergency.access"
$emergencyAdminDisplayName = "AAD Admin - EMERGENCY ACCESS"

# :: AAD Emergency Administrator username
$null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.aadEmergencyAdminUsername -DefaultValue $emergencyAdminUsername
if ($?) {
    Add-LogMessage -Level Success "AAD emergency administrator account username exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create AAD Emergency Global Administrator username!"
}

# :: AAD Emergency Administrator password
$null = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadEmergencyAdminPassword -DefaultLength 20
if ($?) {
    Add-LogMessage -Level Success "AAD emergency administrator account password exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create AAD Emergency Global Administrator password!"
}

# :: Admin usernames
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.domainAdminUsername -DefaultValue "domain$($config.id)admin".ToLower()
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.users.serviceAccounts.aadLocalSync.usernameSecretName -DefaultValue $config.users.serviceAccounts.aadLocalSync.samAccountName
    Add-LogMessage -Level Success "Ensured that SHM admin usernames exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SHM admin usernames exist!"
}
# :: VM admin passwords
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.domainAdminPassword -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.dc.safemodePasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.nps.adminPasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.repository.nexus.adminPasswordSecretName -DefaultLength 20
    foreach ($mirrorType in $config.mirrors.Keys) {
        foreach ($mirrorTier in $config.mirrors[$mirrorType].Keys) {
            foreach ($mirrorDirection in $config.mirrors[$mirrorType][$mirrorTier].Keys) {
                $adminPasswordSecretName = $config.mirrors[$mirrorType][$mirrorTier][$mirrorDirection].adminPasswordSecretName
                if ($adminPasswordSecretName) { $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $adminPasswordSecretName -DefaultLength 20 }
            }
        }
    }
    Add-LogMessage -Level Success "Ensured that SHM VM admin passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SHM VM admin passwords exist!"
}
# :: Computer manager users
try {
    $computerManagers = $config.users.computerManagers
    foreach ($user in $computerManagers.Keys) {
        $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $computerManagers[$user]["passwordSecretName"] -DefaultLength 20
    }
    Add-LogMessage -Level Success "Ensured that domain joining passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that domain joining passwords exist!"
}
# :: Service accounts
try {
    $serviceAccounts = $config.users.serviceAccounts
    foreach ($user in $serviceAccounts.Keys) {
        $null = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $serviceAccounts[$user]["passwordSecretName"] -DefaultLength 20
    }
    Add-LogMessage -Level Success "Ensured that service account passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that service account passwords exist!"
}


# Ensure that Emergency Admin user exists
# ---------------------------------------
# Set user properties
$username = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadEmergencyAdminUsername
$upn = "$username@$($config.domain.fqdn)"
$passwordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
$passwordProfile.Password = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadEmergencyAdminPassword
$passwordProfile.EnforceChangePasswordPolicy = $false
$passwordProfile.ForceChangePasswordNextLogin = $false
$params = @{
    MailNickName = $username
    DisplayName = $emergencyAdminDisplayName
    PasswordProfile = $passwordProfile
    UserType = "Member"
    AccountEnabled = $true
    PasswordPolicies = "DisablePasswordExpiration"
    UsageLocation = $config.organisation.countryCode
}

# Ensure user exists
Add-LogMessage -Level Info "Ensuring AAD emergency administrator account exists..."
$user = Get-AzureADUser | Where-Object { $_.UserPrincipalName -eq $upn }
if($user) {
    # Update existing user
    $user = Set-AzureADUser -ObjectId $upn @params # We must use object ID here. Passing the upn via -UserPrincipalName does not work
    if ($?) {
        Add-LogMessage -Level Success "Existing AAD emergency administrator account updated."
    } else {
        Add-LogMessage -Level Fatal "Failed to update existing AAD emergency administrator account!"
    }
} else {
    $user = New-AzureADUser -UserPrincipalName $upn @params
    if ($?) {
        Add-LogMessage -Level Success "AAD emergency administrator account created."
    } else {
        Add-LogMessage -Level Fatal "Failed to create AAD emergency administrator account!"
    }
}

<# Commented out while awaiting advice from AzureAD powershell module developers on the following error
Line |
 149 |      $null = Add-AzureADDirectoryRoleMember -ObjectId $role.ObjectId - …
     |              ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Error occurred while executing AddDirectoryRoleMember  Code: Request_BadRequest Message: The URI
     | 'https://graph.windows.net//e45911ba-db21-4782-8a2e-4dcdfda486a5/directoryObjects/c15e5037-8d93-4ed4-bd2b-17deb1e1e958'
     |  is not valid since it is not based on 'https://graph.windows.net/e45911ba-db21-4782-8a2e-4dcdfda486a5/'.
     |  RequestId: ed4a51b1-5561-4630-b5f1-a9c6a04184ac DateTimeStamp: Sat, 04 Jul 2020 17:24:44 GMT
     | HttpStatusCode: BadRequest HttpStatusDescription: Bad Request HttpResponseStatus: Completed
# Ensure emergency admin account has full administrator rights
$roleName = "Company Administrator" # 'Company Administrator' is the role name for the AAD 'Global administrator' role
Add-LogMessage -Level Info "Ensuring AAD emergency administrator has '$roleName' role..."
$role = Get-AzureADDirectoryRole | Where-Object {$_.displayName -eq $roleName }
# If role instance does not exist, instantiate it based on the role template
if ($null -eq $role) {
    Add-LogMessage -Level Info "'$roleName' does not exist. Creating role from template."
    # Instantiate an instance of the role template
    $roleTemplate = Get-AzureADDirectoryRoleTemplate | Where-Object {$_.displayName -eq $roleName }
    Enable-AzureADDirectoryRole -RoleTemplateId $roleTemplate.ObjectId
    if ($?) {
        Add-LogMessage -Level Success "'$roleName' created from template."
    } else {
        Add-LogMessage -Level Fatal "Failed to create '$roleName' from template!"
    }
    # Fetch role instance again
    $role = Get-AzureADDirectoryRole | Where-Object {$_.displayName -eq $roleName }
}
# Ensure user is assigned to the role
$user = Get-AzureADUser | Where-Object { $_.UserPrincipalName -eq $upn }
$userHasRole = Get-AzureADDirectoryRoleMember -ObjectId $role.ObjectId | Where-Object { $_.ObjectId -eq $user.ObjectId }
if ($userHasRole) {
    Add-LogMessage -Level Success "AAD emergency administrator already has '$roleName' role."
} else {
    $null = Add-AzureADDirectoryRoleMember -ObjectId $role.ObjectId -RefObjectId $user.ObjectId
    $userHasRole = Get-AzureADDirectoryRoleMember -ObjectId $role.ObjectId | Where-Object { $_.ObjectId -eq $user.ObjectId }
    if($userHasRole) {
        Add-LogMessage -Level Success "Granted AAD emergency administrator '$roleName' role."
    } else {
        Add-LogMessage -Level Failure "Failed to grant AAD emergency administrator '$roleName' role!"
    }
} #>


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
    $vpnCaCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate).Certificate
    $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
    if ($vpnCaCertificate -And $vpnCaCertificatePlain) {
        Add-LogMessage -Level InfoSuccess "Found existing CA certificate"
    } else {
        # Remove any previous certificate with the same name
        # --------------------------------------------------
        Add-LogMessage -Level Info "Creating new self-signed CA certificate..."
        Remove-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate -Force -ErrorAction SilentlyContinue

        # Create self-signed CA certificate with private key
        # --------------------------------------------------
        Add-LogMessage -Level Info "[ ] Generating self-signed certificate locally"
        $vpnCaCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnCaCertPassword -DefaultLength 20
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

        # Store plain CA certificate as a KeyVault secret
        # -----------------------------------------------
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
    Add-LogMessage -Level Info "Ensuring that client certificate exists in the '$($config.keyVault.name)' KeyVault..."
    $vpnClientCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate).Certificate
    if ($vpnClientCertificate) {
        Add-LogMessage -Level InfoSuccess "Found existing client certificate"
    } else {
        # Remove any previous certificate with the same name
        # --------------------------------------------------
        Add-LogMessage -Level Info "Creating new client certificate..."
        Remove-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate -Force -ErrorAction SilentlyContinue

        # Load CA certificate into local PFX file and extract the private key
        # -------------------------------------------------------------------
        Add-LogMessage -Level Info "[ ] Loading CA private key from key vault..."
        $caPfxBase64 = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate).SecretValueText
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
        $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
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
        $vpnClientCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnClientCertPassword -DefaultLength 20
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
$null = Set-AzContext -Context $originalContext
