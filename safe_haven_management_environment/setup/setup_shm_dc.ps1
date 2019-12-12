param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig ($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName

$caValidityMonths = 60 # 5 years
$clientValidityMonths = 24 # 2 years


# Retrieve usernames/passwords from the keyvault
# ------------------------------------
LogMessage -Level Info "Retrieving usernames and passwords..."
$dcNpsAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name -secretName $config.keyVault.secretNames.dcNpsAdminUsername -defaultValue "shm$($config.id)admin".ToLower()
$dcNpsAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name -secretName $config.keyVault.secretNames.dcNpsAdminPassword
$dcSafemodePassword = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name -secretName $config.keyVault.secretNames.dcSafemodePassword


# Generate or retrieve root certificate
# -------------------------------------
LogMessage -Level Info "Ensuring that self-signed CA certificate exists in the '$($config.keyVault.name)' KeyVault..."
$status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate).Status
if ($status -eq "completed") {
    LogMessage -Level Info "[ ] Retrieving existing CA certificate..."
} else {
    LogMessage -Level Info "[ ] Generating self-signed CA certificate..."
    $caPolicy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=SHM-P2S-$($config.id)-CA" -SecretContentType "application/x-pkcs12" `
                                                -ValidityInMonths $caValidityMonths -IssuerName "Self" -KeySize 2048 -KeyType "RSA"
    $caPolicy.Exportable = $true
    $certificateOperation = Add-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate -CertificatePolicy $caPolicy
    while ($status -ne "completed") {
        $status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate).Status
        $progress += 1
        Write-Progress -Activity "Certificate creation:" -Status $status -PercentComplete $progress
        Start-Sleep 1
    }
}
$vpnCaCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificate).Certificate
if ($?) {
    LogMessage -Level Success "Retrieved CA certificate"
} else {
    LogMessage -Level Failure "Failed to retrieve CA certificate!"
}


# Generate or retrieve client certificate
# ---------------------------------------
LogMessage -Level Info "Ensuring that client certificate exists in the '$($config.keyVault.name)' KeyVault..."
$status = (Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate).Status
if ($status -eq "completed") {
    LogMessage -Level Info "[ ] Retrieving existing client certificate..."
} else {
    # Generate a CSR
    # --------------
    $certFolderPath = (New-Item -ItemType "directory" -Path "$((New-TemporaryFile).FullName).certificates").FullName
    $csrPath = Join-Path $certFolderPath "client.csr"
    LogMessage -Level Info "[ ] Generating a certificate signing request at '$csrPath' to be signed by the CA certificate..."
    if ($status -ne "inProgress") {
        $clientPolicy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=SHM-P2S-$($config.id)-Client" -ValidityInMonths $clientValidityMonths -IssuerName "Unknown"
        # $clientPolicy.Exportable = $true
        $_ = Add-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate -CertificatePolicy $clientPolicy
    }
    $certificateOperation = Get-AzKeyVaultCertificateOperation -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate
    $success = $?
    # Write the CSR after reflowing to a maximum of 64 characters per line
    "-----BEGIN CERTIFICATE REQUEST-----" | Out-File -FilePath $csrPath
    $certificateOperation.CertificateSigningRequest -split '(.{64})' | ? {$_} | Out-File -Append -FilePath $csrPath
    "-----END CERTIFICATE REQUEST-----" | Out-File -Append -FilePath $csrPath
    if ($success) {
        LogMessage -Level Success "CSR creation succeeded"
    } else {
        LogMessage -Level Failure "CSR creation failed!"
        throw "Unable to create a certificate signing request for the gateway client!"
    }

    # Load CA certificate (with private key) into local PFX file
    # ----------------------------------------------------------
    LogMessage -Level Info "[ ] Loading CA full certificate (with private key) into local PFX file..."
    $caPfxPath = Join-Path $certFolderPath "ca.pfx"
    $caPfxSecret = Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificate
    $caPfxUnprotectedBytes = [Convert]::FromBase64String($caPfxSecret.SecretValueText)
    [IO.File]::WriteAllBytes($caPfxPath, $caPfxUnprotectedBytes)
    if ($?) {
        LogMessage -Level Success "Loading CA certificate succeeded"
    } else {
        LogMessage -Level Failure "Loading CA certificate failed!"
        throw "Unable to load the CA certificate!"
    }

    # Split CA certificate into key and certificate
    # ---------------------------------------------
    LogMessage -Level Info "[ ] Splitting CA full certificate into key and certificate components..."
    # Write CA key to a file
    $caKeyPath = Join-Path $certFolderPath "ca.key"
    $caKeyPassword = New-Password
    openssl pkcs12 -in $caPfxPath -passin pass: -passout pass:$caKeyPassword -nocerts -out "$($caKeyPath).encrypted" 2>&1 | Out-Null
    openssl rsa -in "$($caKeyPath).encrypted" -passin pass:$caKeyPassword -outform PEM -out $caKeyPath 2>&1 | Out-Null
    $keyMD5 = openssl rsa -noout -modulus -in $caKeyPath | openssl md5
    # Write CA certificate to a file after stripping headers and reflowing to a maximum of 64 characters per line
    $caCrtPath = Join-Path $certFolderPath "ca.crt"
    $caCrtFull = openssl pkcs12 -in $caPfxPath -passin pass: -passout pass: -clcerts -nokeys 2> Out-Null
    $pattern = "-----BEGIN CERTIFICATE-----(.*)-----END CERTIFICATE-----"
    $vpnCaCertificatePlain = [regex]::match($caCrtFull, $pattern).Groups[1].Value -replace " ", ""
    "-----BEGIN CERTIFICATE-----" | Out-File -FilePath $caCrtPath
    $vpnCaCertificatePlain -split '(.{64})' | ? {$_} | Out-File -Append -FilePath $caCrtPath
    "-----END CERTIFICATE-----" | Out-File -Append -FilePath $caCrtPath
    $certMD5 = openssl x509 -noout -modulus -in $caCrtPath | openssl md5
    if ($keyMD5 -eq $certMD5) {
        LogMessage -Level Success "Splitting CA certificate succeeded"
    } else {
        LogMessage -Level Failure "Splitting CA certificate failed!"
        throw "Unable to split the CA certificate!"
    }

    # Sign the client certificate
    # ---------------------------
    LogMessage -Level Info "[ ] Signing the client certificate..."
    $clientCrtPath = Join-Path $certFolderPath "client.crt"
    openssl x509 -req -in $csrPath -CA $caCrtPath -CAkey $caKeyPath -CAcreateserial -out $clientCrtPath -days 360 -sha256 2> Out-Null
    if ((Get-Content $clientCrtPath) -ne $null) {
        LogMessage -Level Success "Signing the client certificate succeeded"
    } else {
        LogMessage -Level Failure "Signing the client certificate failed!"
        throw "Unable to sign the client certificate!"
    }

    # Create PKCS#7 file from full certificate chain and merge it with the private key
    # --------------------------------------------------------------------------------
    LogMessage -Level Info "[ ] Signing the client certificate and merging into the '$($config.keyVault.name)' KeyVault..."
    $clientPkcs7Path = Join-Path $certFolderPath "client.p7b"
    openssl crl2pkcs7 -nocrl -certfile $clientCrtPath -certfile $caCrtPath -out $clientPkcs7Path 2> Out-Null
    $vpnClientCertPassword = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name -secretName $config.keyVault.secretNames.vpnClientCertPassword
    $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnClientCertificate -FilePath $clientPkcs7Path -Password (ConvertTo-SecureString $vpnClientCertPassword -AsPlainText -Force)
    if ($?) {
        LogMessage -Level Success "Importing the signed client certificate succeeded"
    } else {
        LogMessage -Level Failure "Importing the signed client certificate failed!"
        throw "Unable to import the signed client certificate!"
    }

    # Store plain CA certificate as a KeyVault secret
    # -----------------------------------------------
    LogMessage -Level Info "[ ] Storing the plain client certificate (without private key) in the '$($config.keyVault.name)' KeyVault..."
    $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificatePlain -SecretValue (ConvertTo-SecureString $vpnCaCertificatePlain -AsPlainText -Force);
    if ($?) {
        LogMessage -Level Success "Storing the plain client certificate succeeded"
    } else {
        LogMessage -Level Failure "Storing the plain client certificate failed!"
        throw "Unable to store the plain client certificate!"
    }

    # Clean up local files
    # --------------------
    Get-ChildItem $certFolderPath -Recurse | Remove-Item -Recurse
}
$vpnClientCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnClientCertificate).Certificate
if ($?) {
    LogMessage -Level Success "Retrieved CA certificate"
} else {
    LogMessage -Level Failure "Failed to retrieve CA certificate!"
}


# Setup storage account and upload artifacts
# ------------------------------------------
LogMessage -Level Info "Setting up storage account and uploading artifacts..."
$storageAccountRg = $config.storage.artifacts.rg;
$storageAccountName = $config.storage.artifacts.accountName;
$storageAccountLocation = $config.location;
New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
if ($notExists) {
    LogMessage -Level Info "[ ] Creating storage account '$storageAccountName'"
    $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_LRS" -Kind "StorageV2"
    if ($?) {
        LogMessage -Level Success "Created storage account"
    } else {
        LogMessage -Level Failure "Failed to create storage account!"
    }
}

# Create blob storage containers
ForEach ($containerName in ("armdsc", "dcconfiguration", "sre-rds-sh-packages")) {
  if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
    Write-Host " - Creating container '$containerName' in storage account '$storageAccountName'"
    New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
  }
}
# Create file storage shares
ForEach ($shareName in ("sqlserver")) {
  if(-not (Get-AzStorageShare -Context $storageAccount.Context | Where-Object { $_.Name -eq "$shareName" })){
    Write-Host " - Creating share '$shareName' in storage account '$storageAccountName'"
    New-AzStorageShare -Name $shareName -Context $storageAccount.Context;
  }
}

# Upload scripts
Write-Host " - Uploading DSC files to storage account '$storageAccountName'"
Set-AzStorageBlobContent -Container "armdsc" -Context $storageAccount.Context -File "$PSScriptRoot/../arm_templates/shmdc/dscdc1/CreateADPDC.zip" -Force
Set-AzStorageBlobContent -Container "armdsc" -Context $storageAccount.Context -File "$PSScriptRoot/../arm_templates/shmdc/dscdc2/CreateADBDC.zip" -Force

# Artifacts for configuring the DC
Write-Host " - Uploading DC configuration files to storage account '$storageAccountName'"
Set-AzStorageBlobContent -Container "dcconfiguration" -Context $storageAccount.Context -File "$PSScriptRoot/../scripts/shmdc/artifacts/GPOs.zip" -Force
Set-AzStorageBlobContent -Container "dcconfiguration" -Context $storageAccount.Context -File "$PSScriptRoot/../scripts/shmdc/artifacts/Run_ADSync.ps1" -Force

Write-Host " - Uploading SQL server installation files to storage account '$storageAccountName'"
# URI to Azure File copy does not support 302 redirect, so get the latest working endpoint redirected from "https://go.microsoft.com/fwlink/?linkid=853017"
Start-AzStorageFileCopy -AbsoluteUri "https://download.microsoft.com/download/5/E/9/5E9B18CC-8FD5-467E-B5BF-BADE39C51F73/SQLServer2017-SSEI-Expr.exe" -DestShareName "sqlserver" -DestFilePath "SQLServer2017-SSEI-Expr.exe" -DestContext $storageAccount.Context -Force
# URI to Azure File copy does not support 302 redirect, so get the latest working endpoint redirected from "https://go.microsoft.com/fwlink/?linkid=2088649"
Start-AzStorageFileCopy -AbsoluteUri "https://download.microsoft.com/download/5/4/E/54EC1AD8-042C-4CA3-85AB-BA307CF73710/SSMS-Setup-ENU.exe" -DestShareName "sqlserver" -DestFilePath "SSMS-Setup-ENU.exe" -DestContext $storageAccount.Context -Force


# Deploy VNet from template
# -------------------------
$vpnCaCertificatePlain = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificatePlain ).SecretValueText
$vnetCreateParams = @{
  "Virtual_Network_Name" = $config.network.vnet.name
  "P2S_VPN_Certificate" = $vpnCaCertificatePlain
  "VNET_CIDR" = $config.network.vnet.cidr
  "Subnet_Identity_Name" = $config.network.subnets.identity.name
  "Subnet_Identity_CIDR" = $config.network.subnets.identity.cidr
  "Subnet_Web_Name" = $config.network.subnets.web.name
  "Subnet_Web_CIDR" = $config.network.subnets.web.cidr
  "Subnet_Gateway_Name" = $config.network.subnets.gateway.name
  "Subnet_Gateway_CIDR" = $config.network.subnets.gateway.cidr
  "VNET_DNS1" = $config.dc.ip
  "VNET_DNS2" = $config.dcb.ip
}
New-AzResourceGroup -Name $config.network.vnet.rg -Location $config.location -Force
New-AzResourceGroupDeployment -resourcegroupname $config.network.vnet.rg `
                              -templatefile "$PSScriptRoot/../arm_templates/shmvnet/shmvnet-template.json" `
                              @vnetCreateParams -Verbose;


# Deploy SHM-DC from template
# ---------------------------
# Get SAS token
$artifactLocation = "https://" + $config.storage.artifacts.accountName + ".blob.core.windows.net";
$artifactSasToken = (New-AccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg `
  -accountName $config.storage.artifacts.accountName -service Blob,File -resourceType Service,Container,Object `
  -permission "rl" -validityHours 2);
# Check NetBios name
$netbiosNameMaxLength = 15
if($config.domain.netbiosName.length -gt $netbiosNameMaxLength) {
    throw "Netbios name must be no more than 15 characters long. '$($config.domain.netbiosName)' is $($config.domain.netbiosName.length) characters long."
}
New-AzResourceGroup -Name $config.dc.rg  -Location $config.location -Force
New-AzResourceGroupDeployment -resourcegroupname $config.dc.rg `
        -templatefile "$PSScriptRoot/../arm_templates/shmdc/shmdc-template.json"`
        -Administrator_User $dcNpsAdminUsername `
        -Administrator_Password (ConvertTo-SecureString $dcNpsAdminPassword -AsPlainText -Force)`
        -SafeMode_Password (ConvertTo-SecureString $dcSafemodePassword -AsPlainText -Force)`
        -Virtual_Network_Resource_Group $config.network.vnet.rg `
        -Artifacts_Location $artifactLocation `
        -Artifacts_Location_SAS_Token (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)`
        -Domain_Name $config.domain.fqdn `
        -Domain_Name_NetBIOS_Name $config.domain.netbiosName `
        -VM_Size $config.dc.vmSize `
        -Virtual_Network_Name $config.network.vnet.name `
        -Virtual_Network_Subnet $config.network.subnets.identity.name `
        -Shm_Id "$($config.id)".ToLower() `
        -DC1_VM_Name $config.dc.vmName `
        -DC2_VM_Name $config.dcb.vmName `
        -DC1_Host_Name $config.dc.hostname `
        -DC2_Host_Name $config.dcb.hostname `
        -DC1_IP_Address $config.dc.ip `
        -DC2_IP_Address $config.dcb.ip `
        -Verbose;


# Import artifacts from blob storage
# ----------------------------------
Write-Host "Importing configuration artifacts for: $($config.dc.vmName)..."

# Get list of blobs in the storage account
# $storageAccount = Get-AzStorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
$storageContainerName = "dcconfiguration"
$blobNames = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context | ForEach-Object{$_.Name}
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -accountName $config.storage.artifacts.accountName;

# Run import script remotely
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Import_Artifacts.ps1" -Resolve
$params = @{
  remoteDir = "`"C:\Installation`""
  pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
  storageAccountName = "`"$($config.storage.artifacts.accountName)`""
  storageContainerName = "`"$storageContainerName`""
  sasToken = "`"$artifactSasToken`""
}
$result = Invoke-AzVMRunCommand -Name $config.dc.vmName -ResourceGroupName $config.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Configure Active Directory remotely
# -----------------------------------
Write-Host "Configuring Active Directory for: $($config.dc.vmName)..."

# Fetch ADSync user password
$adsyncPassword = EnsureKeyvaultSecret -keyvaultName $config.keyVault.name -secretName $config.keyVault.secretNames.adsyncPassword
$adsyncAccountPasswordEncrypted = ConvertTo-SecureString $adsyncPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)

# Run configuration script remotely
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
$result = Invoke-AzVMRunCommand -Name $config.dc.vmName -ResourceGroupName $config.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Set the OS language to en-GB remotely
# -------------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Set_OS_Language.ps1"
# Run on the primary DC
Write-Host "Setting OS language for: $($config.dc.vmName)..."
$result = Invoke-AzVMRunCommand -Name $config.dc.vmName -ResourceGroupName $config.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
Write-Output $result.Value;
# Run on the secondary DC
Write-Host "Setting OS language for: $($config.dcb.vmName)..."
$result = Invoke-AzVMRunCommand -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
Write-Output $result.Value;


# Configure group policies
# ------------------------
Write-Host "Configuring group policies for: $($config.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Configure_Group_Policies.ps1"
$result = Invoke-AzVMRunCommand -Name $config.dc.vmName -ResourceGroupName $config.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
Write-Output $result.Value;


# Active directory delegation
# ---------------------------
Write-Host "Enabling Active Directory delegation: $($config.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmdc" "remote" "Active_Directory_Delegation.ps1"
$params = @{
  netbiosName = "`"$($config.domain.netbiosName)`""
  ldapUsersGroup = "`"$($config.domain.securityGroups.dsvmLdapUsers.name)`""
}
$result = Invoke-AzVMRunCommand -Name $config.dc.vmName -ResourceGroupName $config.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Switch back to original subscription
# ------------------------------------
Set-AzContext -Context $originalContext;
