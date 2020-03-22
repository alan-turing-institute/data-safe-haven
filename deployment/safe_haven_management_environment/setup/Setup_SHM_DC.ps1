param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# # Ensure that certificates exist
# # ------------------------------
# try {
#     # Define single folder for certificate generation for easier cleanup
#     $certFolderPath = (New-Item -ItemType "directory" -Path "$((New-TemporaryFile).FullName).certificates").FullName

#     # Certificate validities
#     $caValidityDays = 825 # The CAB standard now limits certificates to 825 days
#     $clientValidityDays = 732 # 2 years

#     # Certificate local paths
#     $caStem = "SHM-$($config.id)-P2S-CA".ToUpper()
#     $caCrtPath = Join-Path $certFolderPath "$caStem.crt"
#     $caKeyPath = Join-Path $certFolderPath "$caStem.key"
#     $caPfxPath = Join-Path $certFolderPath "$caStem.pfx"
#     $clientStem = "SHM-$($config.id)-P2S-CLIENT".ToUpper()
#     $clientCrtPath = Join-Path $certFolderPath "$clientStem.crt"
#     $clientCsrPath = Join-Path $certFolderPath "$clientStem.csr"
#     # $clientKeyPath = Join-Path $certFolderPath "$clientStem.key"
#     # $clientPfxPath = Join-Path $certFolderPath "$clientStem.pfx"
#     $clientPkcs7Path = Join-Path $certFolderPath "$clientStem.p7b"

#     # Generate or retrieve CA certificate
#     # -----------------------------------
#     Add-LogMessage -Level Info "Ensuring that self-signed CA certificate exists in the '$($config.keyVault.name)' KeyVault..."
#     $vpnCaCertificate = (Get-AzKeyVaultCertificate -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificate).Certificate
#     $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
#     if ($vpnCaCertificate -And $vpnCaCertificatePlain) {
#         Add-LogMessage -Level InfoSuccess "Found existing CA certificate"
#     } else {
#         # Remove any previous certificate with the same name
#         # --------------------------------------------------
#         Add-LogMessage -Level Info "Creating new self-signed CA certificate..."
#         Remove-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate -Force -ErrorAction SilentlyContinue

#         # Create self-signed CA certificate with private key
#         # --------------------------------------------------
#         Add-LogMessage -Level Info "[ ] Generating self-signed certificate locally"
#         $vpnCaCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnCaCertPassword
#         openssl req -subj "/CN=$caStem" -new -newkey rsa:2048 -sha256 -days $caValidityDays -nodes -x509 -keyout $caKeyPath -out $caCrtPath
#         openssl pkcs12 -in $caCrtPath -inkey $caKeyPath -export -out $caPfxPath -password "pass:$vpnCaCertPassword"
#         if ($?) {
#             Add-LogMessage -Level Success "Generating self-signed certificate succeeded"
#         } else {
#             Add-LogMessage -Level Fatal "Generating self-signed certificate failed!"
#         }

#         # Upload the CA key + cert bundle to the KeyVault
#         # -----------------------------------------------
#         Add-LogMessage -Level Info "[ ] Uploading CA private key + certificate bundle as certificate $($config.keyVault.secretNames.vpnCaCertificate) (includes private key)"
#         $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnCaCertificate -FilePath $caPfxPath -Password (ConvertTo-SecureString $vpnCaCertPassword -AsPlainText -Force);
#         if ($?) {
#             Add-LogMessage -Level Success "Uploading the full CA certificate succeeded"
#         } else {
#             Add-LogMessage -Level Fatal "Uploading the full CA certificate failed!"
#         }

#         # # NB. this is not working at present - OSX reports that the CA certificate "is not standards compliant"
#         # # Generate a self-signed CA certificate in the KeyVault
#         # # -----------------------------------------------------
#         # Add-LogMessage -Level Info "[ ] Generating self-signed certificate in the '$($config.keyVault.name)' KeyVault"
#         # $caPolicy = New-AzKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -KeyType "RSA" -KeySize 2048 `
#         #                                             -SubjectName "CN=$caStem" -ValidityInMonths $caValidityMonths -IssuerName "Self"
#         # $caPolicy.Exportable = $true
#         # $certificateOperation = Add-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate -CertificatePolicy $caPolicy
#         # while ($status -ne "completed") {
#         #     $status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).Status
#         #     $progress = [math]::min(100, $progress + 9)
#         #     Write-Progress -Activity "Certificate creation:" -Status $status -PercentComplete $progress
#         #     Start-Sleep 1
#         # }
#         # if ($?) {
#         #     Add-LogMessage -Level Success "Generating self-signed certificate succeeded"
#         # } else {
#         #     Add-LogMessage -Level Fatal "Generating self-signed certificate failed!"
#         # }

#         # Store plain CA certificate as a KeyVault secret
#         # -----------------------------------------------
#         Add-LogMessage -Level Info "[ ] Uploading the plain CA certificate as secret $($config.keyVault.secretNames.vpnCaCertificatePlain) (without private key)"
#         $vpnCaCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).Certificate
#         # Extract the public certificate and encode it as a Base64 string, without the header and footer lines and with a space every 64 characters
#         $vpnCaCertificateB64String = [System.Convert]::ToBase64String($vpnCaCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
#         $vpnCaCertificatePlain = ($vpnCaCertificateB64String -split '(.{64})' | Where-Object { $_ }) -join " "
#         $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain -SecretValue (ConvertTo-SecureString "$vpnCaCertificatePlain" -AsPlainText -Force)
#         if ($?) {
#             Add-LogMessage -Level Success "Uploading the plain CA certificate succeeded"
#         } else {
#             Add-LogMessage -Level Fatal "Uploading the plain CA certificate failed!"
#         }
#     }

#     # Generate or retrieve client certificate
#     # ---------------------------------------
#     Add-LogMessage -Level Info "Ensuring that client certificate exists in the '$($config.keyVault.name)' KeyVault..."
#     $vpnClientCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate).Certificate
#     if ($vpnClientCertificate) {
#         Add-LogMessage -Level InfoSuccess "Found existing client certificate"
#     } else {
#         # Remove any previous certificate with the same name
#         # --------------------------------------------------
#         Add-LogMessage -Level Info "Creating new client certificate..."
#         Remove-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate -Force -ErrorAction SilentlyContinue

#         # Load CA certificate into local PFX file and extract the private key
#         # -------------------------------------------------------------------
#         Add-LogMessage -Level Info "[ ] Loading CA private key from key vault..."
#         $caPfxBase64 = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificate).SecretValueText
#         [IO.File]::WriteAllBytes($caPfxPath, [System.Convert]::FromBase64String($caPfxBase64))
#         $caKeyData = openssl pkcs12 -in $caPfxPath -nocerts -nodes -passin pass:
#         $caKeyData.Where({ $_ -like "-----BEGIN PRIVATE KEY-----" }, 'SkipUntil') | Out-File -FilePath $caKeyPath
#         $caKeyMD5 = openssl rsa -noout -modulus -in $caKeyPath | openssl md5
#         if ($?) {
#             Add-LogMessage -Level Success "Loading CA private key succeeded"
#         } else {
#             Add-LogMessage -Level Fatal "Loading CA private key failed!"
#         }

#         # Split CA certificate into key and certificate
#         # ---------------------------------------------
#         Add-LogMessage -Level Info "[ ] Retrieving CA plain certificate..."
#         # Write CA certificate to a file after stripping headers and reflowing to a maximum of 64 characters per line
#         $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
#         "-----BEGIN CERTIFICATE-----" | Out-File -FilePath $caCrtPath
#         $vpnCaCertificatePlain.Replace(" ", "") -split '(.{64})' | Where-Object { $_ } | Out-File -Append -FilePath $caCrtPath
#         "-----END CERTIFICATE-----" | Out-File -Append -FilePath $caCrtPath
#         $caCrtMD5 = openssl x509 -noout -modulus -in $caCrtPath | openssl md5
#         if ($caKeyMD5 -eq $caCrtMD5) {
#             Add-LogMessage -Level Success "Validated CA certificate retrieval using MD5"
#         } else {
#             Add-LogMessage -Level Fatal "Failed to validate CA certificate retrieval using MD5!"
#         }

#         # Generate a CSR in the KeyVault
#         # ------------------------------
#         Add-LogMessage -Level Info "[ ] Creating new certificate signing request to be signed by the CA certificate..."
#         if ($status -ne "inProgress") {
#             $clientPolicy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=$clientStem" -ValidityInMonths $clientValidityMonths -IssuerName "Unknown"
#             $_ = Add-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate -CertificatePolicy $clientPolicy
#         }
#         $certificateOperation = Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate
#         $success = $?
#         # Write the CSR after reflowing to a maximum of 64 characters per line
#         "-----BEGIN CERTIFICATE REQUEST-----" | Out-File -FilePath $clientCsrPath
#         $certificateOperation.CertificateSigningRequest -split '(.{64})' | Where-Object { $_ } | Out-File -Append -FilePath $clientCsrPath
#         "-----END CERTIFICATE REQUEST-----" | Out-File -Append -FilePath $clientCsrPath
#         if ($success) {
#             Add-LogMessage -Level Success "CSR creation succeeded"
#         } else {
#             Add-LogMessage -Level Fatal "CSR creation failed!"
#         }

#         # Sign the client certificate - create a PKCS#7 file from full certificate chain and merge it with the private key
#         # ----------------------------------------------------------------------------------------------------------------
#         Add-LogMessage -Level Info "[ ] Signing the CSR and merging into the '$($config.keyVault.secretNames.vpnClientCertificate)' certificate..."
#         $vpnClientCertPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vpnClientCertPassword
#         openssl x509 -req -in $clientCsrPath -CA $caCrtPath -CAkey $caKeyPath -CAcreateserial -out $clientCrtPath -days $clientValidityDays -sha256
#         openssl crl2pkcs7 -nocrl -certfile $clientCrtPath -certfile $caCrtPath -out $clientPkcs7Path 2>&1 | Out-Null
#         $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnClientCertificate -FilePath $clientPkcs7Path -Password (ConvertTo-SecureString "$vpnClientCertPassword" -AsPlainText -Force)
#         if ($?) {
#             Add-LogMessage -Level Success "Importing the signed client certificate succeeded"
#         } else {
#             Add-LogMessage -Level Fatal "Importing the signed client certificate failed!"
#         }
#     }
# } finally {
#     # Delete local copies of certificates and private keys
#     Get-ChildItem $certFolderPath -Recurse | Remove-Item -Recurse
# }

# Setup boot diagnostics resource group and storage account
# ---------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.storage.bootdiagnostics.rg -Location $config.location
$_ = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location


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
#         Add-LogMessage -Level Info "Creating share '$shareName' in storage account '$($config.storage.artifacts.accountName)'"
#         New-AzStorageShare -Name $shareName -Context $storageAccount.Context;
#     }
# }


# Upload artifacts
# ----------------
Add-LogMessage -Level Info "Uploading artifacts to storage account '$($config.storage.artifacts.accountName)'..."
# Upload DSC scripts
Add-LogMessage -Level Info "[ ] Uploading desired state configuration (DSC) files to blob storage"
$_ = Set-AzStorageBlobContent -Container "shm-dsc-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-setup-scripts" "CreateADPDC.zip") -Force
$success = $?
$_ = Set-AzStorageBlobContent -Container "shm-dsc-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc2-setup-scripts" "CreateADBDC.zip") -Force
$success = $success -and $?
if ($success) {
    Add-LogMessage -Level Success "Uploaded desired state configuration (DSC) files"
} else {
    Add-LogMessage -Level Fatal "Failed to upload desired state configuration (DSC) files!"
}
# Upload artifacts for configuring the DC
Add-LogMessage -Level Info "[ ] Uploading domain controller (DC) configuration files to blob storage"
$_ = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "GPOs.zip") -Force
$success = $?
$_ = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "StartMenuLayoutModification.xml") -Force
$success = $success -and $?
$_ = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "Run_ADSync.ps1") -Force
$success = $success -and $?
$_ = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "CreateUsers.ps1") -Force
$success = $success -and $?
# Expand the AD disconnection template before uploading
$adScriptLocalFilePath = (New-TemporaryFile).FullName
$template = Get-Content (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "Disconnect_AD.template.ps1") -Raw
$tmplKeyVaultName = $config.keyvault.secretNames.aadAdminPassword
$tmplAadPasswordName = $config.keyvault.secretNames.aadAdminPassword
$tmplShmFqdn = $config.domain.fqdn
$ExecutionContext.InvokeCommand.ExpandString($template) | Out-File $adScriptLocalFilePath
$_ = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -Blob "Disconnect_AD.ps1" -File $adScriptLocalFilePath -Force
$success = $success -and $?
Remove-Item $adScriptLocalFilePath
if ($success) {
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
# Add-LogMessage -Level Info "Uploading SQL server installation files to storage account '$($config.storage.artifacts.accountName)'"
# # URI to Azure File copy does not support 302 redirect, so get the latest working endpoint redirected from "https://go.microsoft.com/fwlink/?linkid=853017"
# Start-AzStorageFileCopy -AbsoluteUri "https://download.microsoft.com/download/5/E/9/5E9B18CC-8FD5-467E-B5BF-BADE39C51F73/SQLServer2017-SSEI-Expr.exe" -DestShareName "sqlserver" -DestFilePath "SQLServer2017-SSEI-Expr.exe" -DestContext $storageAccount.Context -Force
# # URI to Azure File copy does not support 302 redirect, so get the latest working endpoint redirected from "https://go.microsoft.com/fwlink/?linkid=2088649"
# Start-AzStorageFileCopy -AbsoluteUri "https://download.microsoft.com/download/5/4/E/54EC1AD8-042C-4CA3-85AB-BA307CF73710/SSMS-Setup-ENU.exe" -DestShareName "sqlserver" -DestFilePath "SSMS-Setup-ENU.exe" -DestContext $storageAccount.Context -Force


# Create VNet resource group if it does not exist
# -----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Deploy VNet gateway from template
# ---------------------------------
Add-LogMessage -Level Info "Deploying VNet gateway from template..."
$params = @{
    P2S_VPN_Certificate = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
    Shm_Id = "$($config.id)".ToLower()
    Subnet_Gateway_CIDR = $config.network.subnets.gateway.cidr
    Subnet_Gateway_Name = $config.network.subnets.gateway.Name
    Subnet_Identity_CIDR = $config.network.subnets.identity.cidr
    Subnet_Identity_Name = $config.network.subnets.identity.Name
    Subnet_Web_CIDR = $config.network.subnets.web.cidr
    Subnet_Web_Name = $config.network.subnets.web.Name
    Virtual_Network_Name = $config.network.vnet.Name
    VNET_CIDR = $config.network.vnet.cidr
    VNET_DNS1 = $config.dc.ip
    VNET_DNS2 = $config.dcb.ip
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-vnet-template.json") -Params $params -ResourceGroupName $config.network.vnet.rg


# Create SHM DC resource group if it does not exist
# -------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.dc.rg -Location $config.location


# Retrieve usernames/passwords from the keyvault
# ----------------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.keyVault.name)'..."
$shmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vmAdminUsername -defaultValue "shm$($config.id)admin".ToLower()
$domainAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.domainAdminPassword
$dcSafemodePassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcSafemodePassword


# Deploy SHM DC from template
# ---------------------------
Add-LogMessage -Level Info "Deploying domain controller (DC) from template..."
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
$params = @{
    Administrator_Password = (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)
    Administrator_User = $shmAdminUsername
    Artifacts_Location = "https://" + $config.storage.artifacts.accountName + ".blob.core.windows.net"
    Artifacts_Location_SAS_Token = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)
    BootDiagnostics_Account_Name = $config.storage.bootdiagnostics.accountName
    DC1_Host_Name = $config.dc.hostname
    DC1_IP_Address = $config.dc.ip
    DC1_VM_Name = $config.dc.vmName
    DC2_Host_Name = $config.dcb.hostname
    DC2_IP_Address = $config.dcb.ip
    DC2_VM_Name = $config.dcb.vmName
    Domain_Name = $config.domain.fqdn
    Domain_NetBIOS_Name = $config.domain.netbiosName
    SafeMode_Password = (ConvertTo-SecureString $dcSafemodePassword -AsPlainText -Force)
    Shm_Id = "$($config.id)".ToLower()
    Virtual_Network_Name = $config.network.vnet.Name
    Virtual_Network_Resource_Group = $config.network.vnet.rg
    Virtual_Network_Subnet = $config.network.subnets.identity.Name
    VM_Size = $config.dc.vmSize
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-dc-template.json") -Params $params -ResourceGroupName $config.dc.rg


# Import artifacts from blob storage
# ----------------------------------
Add-LogMessage -Level Info "Importing configuration artifacts for: $($config.dc.vmName)..."
# Get list of blobs in the storage account
$storageContainerName = "shm-configuration-dc"
$blobNames = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context | ForEach-Object { $_.Name }
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Import_Artifacts.ps1" -Resolve
$params = @{
    remoteDir = "`"C:\Installation`""
    pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
    storageAccountName = "`"$($config.storage.artifacts.accountName)`""
    storageContainerName = "`"$storageContainerName`""
    sasToken = "`"$artifactSasToken`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params
Write-Output $result.Value


# Configure Active Directory remotely
# -----------------------------------
Add-LogMessage -Level Info "Configuring Active Directory for: $($config.dc.vmName)..."
# Fetch ADSync user password
$adsyncPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.localAdsyncPassword
$adsyncAccountPasswordEncrypted = ConvertTo-SecureString $adsyncPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Active_Directory_Configuration.ps1"
$params = @{
    oubackuppath = "`"C:\Installation\GPOs`""
    domainou = "`"$($config.domain.dn)`""
    domain = "`"$($config.domain.fqdn)`""
    identitySubnetCidr = "`"$($config.network.subnets.identity.cidr)`""
    webSubnetCidr = "`"$($config.network.subnets.web.cidr)`""
    serverName = "`"$($config.dc.vmName)`""
    serverAdminName = "`"$shmAdminUsername`""
    adsyncAccountPasswordEncrypted = "`"$adsyncAccountPasswordEncrypted`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params
Write-Output $result.Value


# Install required Powershell packages; set the OS language to en-GB then install updates
# ---------------------------------------------------------------------------------------
$installationScriptPath = Join-Path $PSScriptRoot ".." ".." "common" "remote" "Install_Powershell_Modules.ps1"
$configurationScriptPath = Join-Path $PSScriptRoot ".." ".." "common" "remote" "Configure_Windows.ps1"
foreach ($vmName in ($config.dc.vmName, $config.dcb.vmName)) {
    # Install Powershell modules
    Add-LogMessage -Level Info "Installing required Powershell packages on: '$vmName'..."
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $installationScriptPath -VMName $vmName -ResourceGroupName $config.dc.rg
    Write-Output $result.Value
    # Configure Windows
    Add-LogMessage -Level Info "Setting OS language for: '$vmName' and installing updates..."
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $configurationScriptPath -VMName $vmName -ResourceGroupName $config.dc.rg
    Write-Output $result.Value
}

# Set locale, install updates and reboot
# --------------------------------------
foreach ($vmName in ($config.dc.vmName, $config.dcb.vmName)) {
    Add-LogMessage -Level Info "Updating DC VM '$vmName'..."
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.dc.rg -CommonPowershellPath (Join-Path $PSScriptRoot ".." ".." "common")
}

# Configure group policies
# ------------------------
Add-LogMessage -Level Info "Configuring group policies for: $($config.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Configure_Group_Policies.ps1"
$params = @{
    shmFqdn = "`"$($config.domain.fqdn)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params
Write-Output $result.Value


# Active directory delegation
# ---------------------------
Add-LogMessage -Level Info "Enabling Active Directory delegation on: $($config.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Active_Directory_Delegation.ps1"
$params = @{
    netbiosName = "`"$($config.domain.netbiosName)`""
    ldapUsersGroup = "`"$($config.domain.securityGroups.dsvmLdapUsers.name)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params
Write-Output $result.Value


# Restart the DCs
# ---------------
foreach ($vmName in ($config.dc.vmName, $config.dcb.vmName)) {
    Add-LogMessage -Level Info "Restarting $vmName..."
    Enable-AzVM -Name $vmName -ResourceGroupName $config.dc.rg
    if ($?) {
        Add-LogMessage -Level Success "Restarting DC $vmName succeeded"
    } else {
        Add-LogMessage -Level Fatal "Restarting DC $vmName failed!"
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
