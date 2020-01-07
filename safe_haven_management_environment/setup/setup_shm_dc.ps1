param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig ($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


$vpnClientCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnClientCertPassword
$vpnCaCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnCaCertPassword


# $caValidityMonths = 60 # 5 years
# $clientValidityMonths = 24 # 2 years
# $caValidityDays = 2196 # 5 years
$caValidityDays = 825 # The CAB standard now limits certificates to this maximum lifetime
$clientValidityDays = 732 # 2 years


# Define single folder for certificate generation for easier cleanup
$certFolderPath = (New-Item -ItemType "directory" -Path "$((New-TemporaryFile).FullName).certificates").FullName
$caStem = "SHM-$($config.id)-P2S-CA".ToUpper()
$caCrtPath = Join-Path $certFolderPath "$caStem.crt"
$caKeyPath = Join-Path $certFolderPath "$caStem.key"
$caPfxPath = Join-Path $certFolderPath "$caStem.pfx"
$clientStem = "SHM-$($config.id)-P2S-CLIENT".ToUpper()
$clientCrtPath = Join-Path $certFolderPath "$clientStem.crt"
$clientCsrPath = Join-Path $certFolderPath "$clientStem.csr"
$clientKeyPath = Join-Path $certFolderPath "$clientStem.key"
$clientPfxPath = Join-Path $certFolderPath "$clientStem.pfx"


# Generate or retrieve CA certificate
# -----------------------------------
Add-LogMessage -Level Info "Ensuring that self-signed CA certificate exists in the '$($config.keyVault.name)' KeyVault..."
$vpnCaCertificate = (Get-AzKeyVaultCertificate -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificate).Certificate
$vpnCaCertificatePlain = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
if ($vpnCaCertificate -And $vpnCaCertificatePlain) {
    Add-LogMessage -Level Info "Found existing CA certificate..."
} else {
    # Generate CA certificate
    Add-LogMessage -Level Info "Creating new CA certificate..."

    # Create self-signed CA certificate
    openssl req -subj "/CN=$caStem" -new -newkey rsa:2048 -sha256 -days $caValidityDays -nodes -x509 -keyout $caKeyPath -out $caCrtPath
    # Create CA private key + signed cert bundle
    openssl pkcs12 -in $caCrtPath -inkey $caKeyPath -export -out $caPfxPath -password "pass:$vpnCaCertPassword"

    # Store CA cert in KeyVault
    Add-LogMessage -Level Info "Uploading CA cert as secret $($config.keyVault.secretNames.vpnCaCertificatePlain) (no private key)"
    # The certificate only seems to work for the VNET Gateway if the first and last line are removed and it is passed as a single string with spaces removed but *including* new lines
    $certificateString = [string]($(Get-Content -Path $caCrtPath) | Select-Object -Skip 1 | Select-Object -SkipLast 1).replace(" ", "")
    Write-Host "certificateString`n$certificateString"
    $vpnCaCertificatePlain = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnCaCertificatePlain -DefaultValue "$certificateString"

    # Store CA key + cert bundle in KeyVault
    Add-LogMessage -Level Info "Uploading CA private key + cert bundle as certificate $($config.keyVault.secretNames.vpnCaCertificate) (includes private key)"
    $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnCaCertificate -FilePath $caPfxPath -Password (ConvertTo-SecureString $vpnCaCertPassword -AsPlainText -Force);
    Add-LogMessage -Level Success "Created self-signed CA certificate"
}


# Generate or retrieve client certificate
# ---------------------------------------
Add-LogMessage -Level Info "Ensuring that client certificate exists in the '$($config.keyVault.name)' KeyVault..."
$vpnClientCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate).Certificate
if ($vpnClientCertificate) {
    Add-LogMessage -Level Info "Found existing client certificate..."
} else {
    # Generate client certificate
    Add-LogMessage -Level Info "Creating new client certificate..."

    # $clientStem = "SHM-$($config.id)-P2S-CLIENT".ToUpper()
    # $clientKeyPath = Join-Path $certFolderPath "$clientStem.key"
    # $clientCsrPath = Join-Path $certFolderPath "$clientStem.csr"
    # $clientCrtPath = Join-Path $certFolderPath "$clientStem.crt"
    # $clientPfxPath = Join-Path $certFolderPath "$clientStem.pfx"

    # Load CA certificate (with private key) into local PFX file
    # ----------------------------------------------------------
    Add-LogMessage -Level Info "[ ] Loading CA full certificate (with private key) into local PFX file..."
    $caPfxBase64 = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).SecretValueText
    [IO.File]::WriteAllBytes($caPfxPath, [Convert]::FromBase64String($caPfxBase64))
    if ($?) {
        Add-LogMessage -Level Success "Loading CA full certificate succeeded"
    } else {
        Add-LogMessage -Level Fatal "Loading CA full certificate failed!"
    }

    # Split CA certificate into key and certificate
    # ---------------------------------------------
    Add-LogMessage -Level Info "[ ] Splitting CA full certificate into key and certificate components..."
    # Write CA key to a file
    $caKeyData = openssl pkcs12 -in $caPfxPath -nocerts -nodes -passin pass:
    Write-Host "previous key`n$(Get-Content $caKeyPath -Raw)"
    $caKeyData.Where({ $_ -like "-----BEGIN PRIVATE KEY-----" }, 'SkipUntil') | Out-File -FilePath $caKeyPath
    Write-Host "new key`n$(Get-Content $caKeyPath -Raw)"
    $caKeyMD5 = openssl rsa -noout -modulus -in $caKeyPath | openssl md5
    # Write CA certificate to a file after stripping headers and reflowing to a maximum of 64 characters per line
    # $vpnCaCertificatePlain = [string]((Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText).replace(" ", "")
    $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText

    Write-Host "raw certificate:`n$vpnCaCertificatePlain"

    Write-Host "previous cert`n$(Get-Content $caCrtPath -Raw)"
    "-----BEGIN CERTIFICATE-----" | Out-File -FilePath $caCrtPath
    $vpnCaCertificatePlain.Replace(" ", "") -split '(.{64})' | Where-Object { $_ } | Out-File -Append -FilePath $caCrtPath
    "-----END CERTIFICATE-----" | Out-File -Append -FilePath $caCrtPath
    Write-Host "new cert`n$(Get-Content $caCrtPath -Raw)"
    $caCrtMD5 = openssl x509 -noout -modulus -in $caCrtPath | openssl md5
    if ($caKeyMD5 -eq $caCrtMD5) {
        Add-LogMessage -Level Success "Validated CA certificate splitting using MD5"
    } else {
        Add-LogMessage -Level Fatal "Failed to validate CA certificate splitting using MD5!"
    }

    # Create client key
    openssl genrsa -out $clientKeyPath 2048
    # Create client CSR
    openssl req -new -sha256 -key $clientKeyPath -subj "/CN=$clientStem" -out $clientCsrPath
    # Sign client certificate
    openssl x509 -req -in $clientCsrPath -CA $caCrtPath -CAkey $caKeyPath -CAcreateserial -out $clientCrtPath -days $clientValidityDays -sha256
    # Create client private key + signed cert bundle
    openssl pkcs12 -in $clientCrtPath -inkey $clientKeyPath -certfile $caCrtPath -export -out $clientPfxPath -password "pass:$vpnClientCertPassword"

    # Store client key + cert bundle in KeyVault
    Add-LogMessage -Level Info "Uploading client private key + cert bundle as certificate $($config.keyVault.secretNames.vpnClientCertificate) (includes private key)"
    $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnClientCertificate -FilePath $clientPfxPath -Password (ConvertTo-SecureString $vpnClientCertPassword -AsPlainText -Force);
    Add-LogMessage -Level Success "Created signed client certificate"
}
# Delete local copies of certificates and private keys
Get-ChildItem $certFolderPath -Recurse | Remove-Item -Recurse



# # Generate or retrieve root certificate
# # -------------------------------------
# Add-LogMessage -Level Info "Ensuring that self-signed CA certificate exists in the '$($config.keyVault.name)' KeyVault..."
# $status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).Status
# if ($status -eq "completed") {
#     Add-LogMessage -Level Info "[ ] Retrieving existing CA certificate..."
# } else {
#     $certFolderPath = (New-Item -ItemType "directory" -Path "$((New-TemporaryFile).FullName).certificates").FullName

#     # Generate certificates
#     Write-Host "===Started creating certificates==="

#     # Create self-signed CA certificate
#     $caKeyPath = Join-Path $certFolderPath "ca.key"
#     $caCrtPath = Join-Path $certFolderPath "ca.crt"
#     $caPfxPath = Join-Path $certFolderPath "ca.pfx"
#     openssl req -subj "/CN=SHM-$($($config.id).ToUpper())-P2S-CA" -new -newkey rsa:2048 -sha256 -days $caValidityDays -nodes -x509 -keyout $caKeyPath -out $caCrtPath

#     # Store plain CA cert in KeyVault
#     Write-Host "Storing plain CA cert in '$($config.keyVault.name)' KeyVault as secret $($config.keyVault.secretNames.vpnCaCertificatePlain) (no private key)"
#     # The certificate only seems to work for the VNET Gateway if the first and last line are removed and it is passed as a single string with white space removed
#     $vpnCaCertificatePlain = $(Get-Content -Path "$caCrtPath") | Select-Object -Skip 1 | Select-Object -SkipLast 1
#     $vpnCaCertificatePlain = [string]$vpnCaCertificatePlain
#     $vpnCaCertificatePlain = $vpnCaCertificatePlain.replace(" ", "")
#     $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificatePlain -SecretValue (ConvertTo-SecureString $vpnCaCertificatePlain -AsPlainText -Force);

#     # Create CA private key + signed cert bundle
#     $vpnCaCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnCaCertPassword
#     Write-Host "vpnCaCertPassword: $vpnCaCertPassword"
#     openssl pkcs12 -in "$caCrtPath" -inkey "$caKeyPath" -export -out "$caPfxPath" -password "pass:$vpnCaCertPassword"

#     # Store CA key + cert bundle in KeyVault
#     Write-Host "Storing CA private key + cert bundle in '$($config.keyVault.name)' KeyVault as certificate $($config.keyVault.secretNames.vpnCaCertificate) (includes private key)"
#     $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnCaCertificate -FilePath "$caPfxPath" -Password (ConvertTo-SecureString $vpnCaCertPassword -AsPlainText -Force);


#     # # Generate a self-signed CA certificate
#     # # -------------------------------------
#     # Add-LogMessage -Level Info "[ ] Generating self-signed CA certificate..."
#     # $caPolicy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=SHM-$($($config.id).ToUpper())-P2S-CA" -SecretContentType "application/x-pkcs12" `
#     #                                             -ValidityInMonths $caValidityMonths -IssuerName "Self" -KeySize 2048 -KeyType "RSA" -KeyUsage "KeyCertSign"
#     # $caPolicy.Exportable = $true
#     # $certificateOperation = Add-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate -CertificatePolicy $caPolicy
#     # while ($status -ne "completed") {
#     #     $status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).Status
#     #     $progress += 1
#     #     Write-Progress -Activity "Certificate creation:" -Status $status -PercentComplete $progress
#     #     Start-Sleep 1
#     # }

#     # # Store plain CA certificate as a KeyVault secret
#     # # -----------------------------------------------
#     # Add-LogMessage -Level Info "[ ] Storing the plain client certificate (without private key) in the '$($config.keyVault.name)' KeyVault..."
#     # $vpnCaCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).Certificate
#     # # Extract the public certificate and encode it as a Base64 string
#     # $vpnCaCertificatePlain = [System.Convert]::ToBase64String($vpnCaCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
#     # $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain -SecretValue (ConvertTo-SecureString $vpnCaCertificatePlain -AsPlainText -Force)
#     # if ($?) {
#     #     Add-LogMessage -Level Success "Storing the plain client certificate succeeded"
#     # } else {
#     #     Add-LogMessage -Level Fatal "Storing the plain client certificate failed!"
#     # }


#     # Clean up local files
#     # --------------------
#     # Write-Host "local CRT`n$(Get-Content $caCrtPath -Raw)"
#     # Write-Host "local key`n$(Get-Content $caKeyPath -Raw)"
#     Get-ChildItem $certFolderPath -Recurse | Remove-Item -Recurse
# }
# $_ = Get-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate
# if ($?) {
#     Add-LogMessage -Level Success "Retrieved CA certificate"
# } else {
#     Add-LogMessage -Level Fatal "Failed to retrieve CA certificate!"
# }


# # Generate or retrieve client certificate
# # ---------------------------------------
# Add-LogMessage -Level Info "Ensuring that client certificate exists in the '$($config.keyVault.name)' KeyVault..."
# $status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate).Status
# if ($status -eq "completed") {
#     Add-LogMessage -Level Info "[ ] Retrieving existing client certificate..."
# } else {
#     $certFolderPath = (New-Item -ItemType "directory" -Path "$((New-TemporaryFile).FullName).certificates").FullName
#     # # Generate a CSR
#     # # --------------
#     # $certFolderPath = (New-Item -ItemType "directory" -Path "$((New-TemporaryFile).FullName).certificates").FullName
#     # $csrPath = Join-Path $certFolderPath "client.csr"
#     # Add-LogMessage -Level Info "[ ] Generating a certificate signing request at '$csrPath' to be signed by the CA certificate..."
#     # if ($status -ne "inProgress") {
#     #     $clientPolicy = New-AzKeyVaultCertificatePolicy -SubjectName "/CN=SHM-$($($config.id).ToUpper())-P2S-CLIENT" -ValidityInMonths $clientValidityMonths -IssuerName "Unknown"
#     #     $_ = Add-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate -CertificatePolicy $clientPolicy
#     # }
#     # $certificateOperation = Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate
#     # $success = $?
#     # # Write the CSR after reflowing to a maximum of 64 characters per line
#     # "-----BEGIN CERTIFICATE REQUEST-----" | Out-File -FilePath $csrPath
#     # $certificateOperation.CertificateSigningRequest -split '(.{64})' | Where-Object { $_ } | Out-File -Append -FilePath $csrPath
#     # "-----END CERTIFICATE REQUEST-----" | Out-File -Append -FilePath $csrPath
#     # if ($success) {
#     #     Add-LogMessage -Level Success "CSR creation succeeded"
#     # } else {
#     #     Add-LogMessage -Level Fatal "CSR creation failed!"
#     # }

#     # Generate client CSR
#     # -------------------
#     $clientKeyPath = Join-Path $certFolderPath "client.key"
#     $clientCsrPath = Join-Path $certFolderPath "client.csr"
#     openssl genrsa -out $clientKeyPath 2048
#     openssl req -new -sha256 -key $clientKeyPath -subj "/CN=SHM-$($($config.id).ToUpper())-P2S-CLIENT" -out $clientCsrPath


#     # Load CA certificate (with private key) into local PFX file
#     # ----------------------------------------------------------
#     Add-LogMessage -Level Info "[ ] Loading CA full certificate (with private key) into local PFX file..."
#     $caPfxPath = Join-Path $certFolderPath "ca.pfx"
#     $caPfxBase64 = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).SecretValueText
#     [IO.File]::WriteAllBytes($caPfxPath, [Convert]::FromBase64String($caPfxBase64))
#     if ($?) {
#         Add-LogMessage -Level Success "Loading CA certificate succeeded"
#     } else {
#         Add-LogMessage -Level Fatal "Loading CA certificate failed!"
#     }

#     # Split CA certificate into key and certificate
#     # ---------------------------------------------
#     Add-LogMessage -Level Info "[ ] Splitting CA full certificate into key and certificate components..."
#     # Write CA key to a file
#     $caKeyPath = Join-Path $certFolderPath "ca.key"
#     $caKeyData = openssl pkcs12 -in $caPfxPath -nocerts -nodes -passin pass:
#     $caKeyData.Where({ $_ -like "-----BEGIN PRIVATE KEY-----" }, 'SkipUntil') | Out-File -FilePath $caKeyPath
#     $caKeyMD5 = openssl rsa -noout -modulus -in $caKeyPath | openssl md5
#     # Write CA certificate to a file after stripping headers and reflowing to a maximum of 64 characters per line
#     $caCrtPath = Join-Path $certFolderPath "ca.crt"
#     $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
#     "-----BEGIN CERTIFICATE-----" | Out-File -FilePath $caCrtPath
#     $vpnCaCertificatePlain -split '(.{64})' | Where-Object { $_ } | Out-File -Append -FilePath $caCrtPath
#     "-----END CERTIFICATE-----" | Out-File -Append -FilePath $caCrtPath
#     $caCrtMD5 = openssl x509 -noout -modulus -in $caCrtPath | openssl md5
#     if ($caKeyMD5 -eq $caCrtMD5) {
#         Add-LogMessage -Level Success "Validated CA certificate splitting using MD5"
#     } else {
#         Add-LogMessage -Level Failure "Failed to validate CA certificate splitting using MD5!"
#         throw "Failed to validate CA certificate splitting using MD5!"
#     }


#     # # Sign the client certificate
#     # # ---------------------------
#     # Add-LogMessage -Level Info "[ ] Signing the client certificate..."
#     # $clientCrtPath = Join-Path $certFolderPath "client.crt"
#     # openssl x509 -req -in $csrPath -CA $caCrtPath -CAkey $caKeyPath -CAcreateserial -out $clientCrtPath -days 360 -sha256 2>&1 | Out-Null
#     # if ((Get-Content $clientCrtPath) -ne $null) {
#     #     Add-LogMessage -Level Success "Signing the client certificate succeeded"
#     # } else {
#     #     Add-LogMessage -Level Fatal "Signing the client certificate failed!"
#     # }

#     # Sign the client certificate
#     # ---------------------------
#     $vpnClientCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnClientCertPassword
#     Write-Host "vpnClientCertPassword: '$vpnClientCertPassword' $($vpnClientCertPassword.GetType())"
#     $clientCrtPath = Join-Path $certFolderPath "client.crt"
#     $clientPfxPath = Join-Path $certFolderPath "client.pfx"
#     openssl x509 -req -in $clientCsrPath -CA $caCrtPath -CAkey $caKeyPath -CAcreateserial -out $clientCrtPath -days $clientValidityDays -sha256
#     openssl pkcs12 -in "$clientCrtPath" -inkey "$clientKeyPath" -certfile $caCrtPath -export -out "$clientPfxPath" -password "pass:$vpnClientCertPassword"

#     # Store the client key + certificate bundle in the KeyVault
#     # ---------------------------------------------------------
#     Write-Host "Storing Client private key + cert bundle in '$($config.keyVault.name)' KeyVault as certificate $($config.keyVault.secretNames.vpnClientCertificate) (includes private key)"
#     $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnClientCertificate -FilePath "$clientPfxPath" -Password (ConvertTo-SecureString $vpnClientCertPassword -AsPlainText -Force);


#     # # Create PKCS#7 file from full certificate chain and merge it with the private key
#     # # --------------------------------------------------------------------------------
#     # Add-LogMessage -Level Info "[ ] Signing the client certificate and merging into the '$($config.keyVault.name)' KeyVault..."
#     # $clientPkcs7Path = Join-Path $certFolderPath "client.p7b"
#     # openssl crl2pkcs7 -nocrl -certfile $clientCrtPath -certfile $caCrtPath -out $clientPkcs7Path 2>&1 | Out-Null
#     # $vpnClientCertPassword = [string](Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnClientCertPassword)
#     # $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate -FilePath $clientPkcs7Path -Password (ConvertTo-SecureString $vpnClientCertPassword -AsPlainText -Force)
#     # if ($?) {
#     #     Add-LogMessage -Level Success "Importing the signed client certificate succeeded"
#     # } else {
#     #     Add-LogMessage -Level Fatal "Importing the signed client certificate failed!"
#     # }

#     # Clean up local files
#     # --------------------
#     # Write-Host "remote CRT`n$(Get-Content $caCrtPath -Raw)"
#     # Write-Host "remote key`n$(Get-Content $caKeyPath -Raw)"
#     Get-ChildItem $certFolderPath -Recurse | Remove-Item -Recurse
# }
# $_ = Get-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate
# if ($?) {
#     Add-LogMessage -Level Success "Retrieved client certificate"
# } else {
#     Add-LogMessage -Level Fatal "Failed to retrieve client certificate!"
# }
# # exit 1


# Setup boot diagnostics resource group and storage account
# ---------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.bootdiagnostics.rg -Location $config.location
$_ = Deploy-StorageAccount -Name $config.bootdiagnostics.accountName -ResourceGroupName $config.bootdiagnostics.rg -Location $config.location


# Setup artifacts resource group and storage account
# --------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.storage.artifacts.rg -Location $config.location
$storageAccount = Deploy-StorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -Location $config.location


# Create blob storage containers
# ------------------------------
Add-LogMessage -Level Info "Ensuring that blob storage containers exist..."
foreach ($containerName in ("shm-dsc-dc", "shm-configuration-dc", "sre-rds-sh-packages")) {
    $_ = Deploy-StorageContainer -Name $containerName -StorageAccount $storageAccount
}
# NB. we would like the NPS VM to log to a database, but this is not yet working
# # Create file storage shares
# foreach ($shareName in ("sqlserver")) {
#     if (-not (Get-AzStorageShare -Context $storageAccount.Context | Where-Object { $_.Name -eq "$shareName" })) {
#         Write-Host " - Creating share '$shareName' in storage account '$($config.storage.artifacts.accountName)'"
#         New-AzStorageShare -Name $shareName -Context $storageAccount.Context;
#     }
# }


# Upload artifacts
# ----------------
Add-LogMessage -Level Info "Uploading artifacts to storage account '$($config.storage.artifacts.accountName)'..."
# Upload DSC scripts
Add-LogMessage -Level Info "[ ] Uploading desired state configuration (DSC) files to blob storage"
$_ = Set-AzStorageBlobContent -Container "shm-dsc-dc" -Context $storageAccount.Context -File "$PSScriptRoot/../arm_templates/shmdc/dscdc1/CreateADPDC.zip" -Force
$success = $?
$_ = Set-AzStorageBlobContent -Container "shm-dsc-dc" -Context $storageAccount.Context -File "$PSScriptRoot/../arm_templates/shmdc/dscdc2/CreateADBDC.zip" -Force
$success = $success -and $?
if ($?) {
    Add-LogMessage -Level Success "Uploaded desired state configuration (DSC) files"
} else {
    Add-LogMessage -Level Fatal "Failed to upload desired state configuration (DSC) files!"
}
# Upload artifacts for configuring the DC
Add-LogMessage -Level Info "[ ] Uploading domain controller (DC) configuration files to blob storage"
$_ = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File "$PSScriptRoot/../scripts/shmdc/artifacts/GPOs.zip" -Force
$success = $?
$_ = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File "$PSScriptRoot/../scripts/shmdc/artifacts/Run_ADSync.ps1" -Force
$success = $success -and $?
if ($?) {
    Add-LogMessage -Level Success "Uploaded domain controller (DC) configuration files"
} else {
    Add-LogMessage -Level Fatal "Failed to upload domain controller (DC) configuration files!"
}
# Upload Windows package installers
Add-LogMessage -Level Info "[ ] Uploading Windows package installers to blob storage"
$success = $true
# Chrome
$filename = "GoogleChromeStandaloneEnterprise64.msi"
Start-AzStorageBlobCopy -AbsoluteUri "http://dl.google.com/edgedl/chrome/install/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "GoogleChrome_x64.msi" -DestContext $storageAccount.Context -Force
$success = $success -and $?
# LibreOffice
$baseUri = "https://downloadarchive.documentfoundation.org/libreoffice/old/latest/win/x86_64/"
$httpContent = Invoke-WebRequest -URI $baseUri
$filename = $httpContent.Links | Where-Object { $_.href -like "*Win_x64.msi" } | % { $_.href }
Start-AzStorageBlobCopy -AbsoluteUri "$baseUri/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "LibreOffice_x64.msi" -DestContext $storageAccount.Context -Force
$success = $success -and $?
# PuTTY
$baseUri = "https://the.earth.li/~sgtatham/putty/latest/w64/"
$httpContent = Invoke-WebRequest -URI $baseUri
$filename = $httpContent.Links | Where-Object { $_.href -like "*installer.msi" } | % { $_.href }
$version = ($filename -split "-")[2]
Start-AzStorageBlobCopy -AbsoluteUri "$($baseUri.Replace('latest', $version))/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "PuTTY_x64.msi" -DestContext $storageAccount.Context -Force
$success = $success -and $?
# WinSCP
$httpContent = Invoke-WebRequest -URI "https://winscp.net/eng/download.php"
$filename = $httpContent.Links  | Where-Object { $_.href -like "*Setup.exe" } | % { ($_.href -split "/")[-1] }
$absoluteUri = (Invoke-WebRequest -URI "https://winscp.net/download/$filename").Links | Where-Object { $_.href -like "*$filename" } | % { $_.href }
Start-AzStorageBlobCopy -AbsoluteUri "$absoluteUri" -DestContainer "sre-rds-sh-packages" -DestBlob "WinSCP_x32.exe" -DestContext $storageAccount.Context -Force
$success = $success -and $?
if ($success) {
    Add-LogMessage -Level Success "Uploaded Windows package installers"
} else {
    Add-LogMessage -Level Fatal "Failed to upload Windows package installers!"
}
# NB. we would like the NPS VM to log to a database, but this is not yet working
# Write-Host " - Uploading SQL server installation files to storage account '$($config.storage.artifacts.accountName)'"
# # URI to Azure File copy does not support 302 redirect, so get the latest working endpoint redirected from "https://go.microsoft.com/fwlink/?linkid=853017"
# Start-AzStorageFileCopy -AbsoluteUri "https://download.microsoft.com/download/5/E/9/5E9B18CC-8FD5-467E-B5BF-BADE39C51F73/SQLServer2017-SSEI-Expr.exe" -DestShareName "sqlserver" -DestFilePath "SQLServer2017-SSEI-Expr.exe" -DestContext $storageAccount.Context -Force
# # URI to Azure File copy does not support 302 redirect, so get the latest working endpoint redirected from "https://go.microsoft.com/fwlink/?linkid=2088649"
# Start-AzStorageFileCopy -AbsoluteUri "https://download.microsoft.com/download/5/4/E/54EC1AD8-042C-4CA3-85AB-BA307CF73710/SSMS-Setup-ENU.exe" -DestShareName "sqlserver" -DestFilePath "SSMS-Setup-ENU.exe" -DestContext $storageAccount.Context -Force


# Create VNet resource group if it does not exist
# -----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Deploy VNet from template
# -------------------------
Add-LogMessage -Level Info "Deploying VNet from template..."
$params = @{
    Virtual_Network_Name = $config.network.vnet.Name
    P2S_VPN_Certificate = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
    VNET_CIDR = $config.network.vnet.cidr
    Subnet_Identity_Name = $config.network.subnets.identity.Name
    Subnet_Identity_CIDR = $config.network.subnets.identity.cidr
    Subnet_Web_Name = $config.network.subnets.web.Name
    Subnet_Web_CIDR = $config.network.subnets.web.cidr
    Subnet_Gateway_Name = $config.network.subnets.gateway.Name
    Subnet_Gateway_CIDR = $config.network.subnets.gateway.cidr
    VNET_DNS1 = $config.dc.ip
    VNET_DNS2 = $config.dcb.ip
}
Deploy-ArmTemplate -TemplatePath "$PSScriptRoot/../arm_templates/shmvnet/shm-vnet-template.json" -Params $params -ResourceGroupName $config.network.vnet.rg
exit 1

# Create SHM DC resource group if it does not exist
# ---------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.dc.rg -Location $config.location


# Retrieve usernames/passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.keyVault.name)'..."
$dcNpsAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcNpsAdminUsername -defaultValue "shm$($config.id)admin".ToLower()
$dcNpsAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcNpsAdminPassword
$dcSafemodePassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcSafemodePassword


# Deploy SHM DC from template
# ---------------------------
Add-LogMessage -Level Info "Deploying domain controller (DC) from template..."
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
$params = @{
    Administrator_Password = (ConvertTo-SecureString $dcNpsAdminPassword -AsPlainText -Force)
    Administrator_User = $dcNpsAdminUsername
    Artifacts_Location = "https://" + $config.storage.artifacts.accountName + ".blob.core.windows.net"
    Artifacts_Location_SAS_Token = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)
    BootDiagnostics_Account_Name = $config.bootdiagnostics.accountName
    DC1_Host_Name = $config.dc.hostname
    DC1_IP_Address = $config.dc.ip
    DC1_VM_Name = $config.dc.vmName
    DC2_Host_Name = $config.dcb.hostname
    DC2_IP_Address = $config.dcb.ip
    DC2_VM_Name = $config.dcb.vmName
    Domain_Name = $config.domain.fqdn
    Domain_Name_NetBIOS_Name = $config.domain.netbiosName
    SafeMode_Password = (ConvertTo-SecureString $dcSafemodePassword -AsPlainText -Force)
    Shm_Id = "$($config.id)".ToLower()
    Virtual_Network_Name = $config.network.vnet.Name
    Virtual_Network_Resource_Group = $config.network.vnet.rg
    Virtual_Network_Subnet = $config.network.subnets.identity.Name
    VM_Size = $config.dc.vmSize
}
Deploy-ArmTemplate -TemplatePath "$PSScriptRoot/../arm_templates/shmdc/shm-dc-template.json" -Params $params -ResourceGroupName $config.dc.rg


# Import artifacts from blob storage
# ----------------------------------
Add-LogMessage -Level Info "Importing configuration artifacts for: $($config.dc.vmName)..."
# Get list of blobs in the storage account
$storageContainerName = "shm-configuration-dc"
$blobNames = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context | ForEach-Object { $_.Name }
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Import_Artifacts.ps1" -Resolve
$params = @{
    remoteDir = "`"C:\Installation`""
    pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
    storageAccountName = "`"$($config.storage.artifacts.accountName)`""
    storageContainerName = "`"$storageContainerName`""
    sasToken = "`"$artifactSasToken`""
}
Invoke-LoggedRemotePowershell -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params


# Configure Active Directory remotely
# -----------------------------------
Add-LogMessage -Level Info "Configuring Active Directory for: $($config.dc.vmName)..."
# Fetch ADSync user password
$adsyncPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.adsyncPassword
$adsyncAccountPasswordEncrypted = ConvertTo-SecureString $adsyncPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Active_Directory_Configuration.ps1"
$params = @{
    oubackuppath = "`"C:\Installation\GPOs`""
    domainou = "`"$($config.domain.dn)`""
    domain = "`"$($config.domain.fqdn)`""
    identitySubnetCidr = "`"$($config.network.subnets.identity.cidr)`""
    webSubnetCidr = "`"$($config.network.subnets.web.cidr)`""
    serverName = "`"$($config.dc.vmName)`""
    serverAdminName = "`"$dcNpsAdminUsername`""
    adsyncAccountPasswordEncrypted = "`"$adsyncAccountPasswordEncrypted`""
}
Invoke-LoggedRemotePowershell -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params


# Set the OS language to en-GB remotely
# -------------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Set_OS_Language.ps1"
foreach ($vmName in ($config.dc.vmName, $config.dcb.vmName)) {
    Add-LogMessage -Level Info "Setting OS language for: $vmName..."
    Invoke-LoggedRemotePowershell -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.dc.rg
}


# Configure group policies
# ------------------------
Add-LogMessage -Level Info "Configuring group policies for: $($config.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Configure_Group_Policies.ps1"
Invoke-LoggedRemotePowershell -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg


# Active directory delegation
# ---------------------------
Add-LogMessage -Level Info "Enabling Active Directory delegation on: $($config.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Active_Directory_Delegation.ps1"
$params = @{
    netbiosName = "`"$($config.domain.netbiosName)`""
    ldapUsersGroup = "`"$($config.domain.securityGroups.dsvmLdapUsers.name)`""
}
Invoke-LoggedRemotePowershell -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params


# Switch back to original subscription
# ------------------------------------
Set-AzContext -Context $originalContext;
