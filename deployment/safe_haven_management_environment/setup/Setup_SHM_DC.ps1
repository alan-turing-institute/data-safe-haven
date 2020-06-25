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
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Setup boot diagnostics resource group and storage account
# ---------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.storage.bootdiagnostics.rg -Location $config.location
$null = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location


# Setup artifacts resource group and storage account
# --------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.storage.artifacts.rg -Location $config.location
$storageAccount = Deploy-StorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -Location $config.location


# Create blob storage containers
# ------------------------------
Add-LogMessage -Level Info "Ensuring that blob storage containers exist..."
foreach ($containerName in ("shm-dsc-dc", "shm-configuration-dc", "sre-rds-sh-packages")) {
    $null = Deploy-StorageContainer -Name $containerName -StorageAccount $storageAccount
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
$null = Set-AzStorageBlobContent -Container "shm-dsc-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-setup-scripts" "CreateADPDC.zip") -Force
$success = $?
$null = Set-AzStorageBlobContent -Container "shm-dsc-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc2-setup-scripts" "CreateADBDC.zip") -Force
$success = $success -and $?
if ($success) {
    Add-LogMessage -Level Success "Uploaded desired state configuration (DSC) files"
} else {
    Add-LogMessage -Level Fatal "Failed to upload desired state configuration (DSC) files!"
}
# Upload artifacts for configuring the DC
Add-LogMessage -Level Info "[ ] Uploading domain controller (DC) configuration files to blob storage"
$null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "CreateUsers.ps1") -Force
$success = $success -and $?
$null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "GPOs.zip") -Force
$success = $?
$null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "Run_ADSync.ps1") -Force
$success = $success -and $?
$null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "StartMenuLayoutModification.xml") -Force
$success = $success -and $?
$null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "UpdateAADSyncRule.ps1") -Force
$success = $success -and $?
$null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "user_details_template.csv") -Force
$success = $success -and $?
# Expand the AD disconnection template before uploading
$adScriptLocalFilePath = (New-TemporaryFile).FullName
$adScriptTemplate = Get-Content (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration" "Disconnect_AD.template.ps1") -Raw
$adScriptTemplate.Replace('<shm-keyvault-name>', $config.keyvault.name).
                  Replace('<aad-admin-password-name>', $config.keyvault.secretNames.aadAdminPassword).
                  Replace('<shm-fqdn>', $config.domain.fqdn) | Out-File $adScriptLocalFilePath
$null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -Blob "Disconnect_AD.ps1" -File $adScriptLocalFilePath -Force
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
$filename = $httpContent.Links | Where-Object { $_.href -like "*Win_x64.msi" } | ForEach-Object { $_.href } | Select-Object -First 1
Start-AzStorageBlobCopy -AbsoluteUri "$baseUri/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "LibreOffice_x64.msi" -DestContext $storageAccount.Context -Force
$success = $success -and $?
# PuTTY
$baseUri = "https://the.earth.li/~sgtatham/putty/latest/w64/"
$httpContent = Invoke-WebRequest -URI $baseUri
$filename = $httpContent.Links | Where-Object { $_.href -like "*installer.msi" } | ForEach-Object { $_.href } | Select-Object -First 1
$version = ($filename -split "-")[2]
Start-AzStorageBlobCopy -AbsoluteUri "$($baseUri.Replace('latest', $version))/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "PuTTY_x64.msi" -DestContext $storageAccount.Context -Force
$success = $success -and $?
# WinSCP
$httpContent = Invoke-WebRequest -URI "https://winscp.net/eng/download.php"
$filename = $httpContent.Links | Where-Object { $_.href -like "*Setup.exe" } | ForEach-Object { ($_.href -split "/")[-1] }
$absoluteUri = (Invoke-WebRequest -URI "https://winscp.net/download/$filename").Links | Where-Object { $_.href -like "*winscp.net*$filename*" } | ForEach-Object { $_.href } | Select-Object -First 1
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
$null = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Deploy VNet gateway from template
# ---------------------------------
Add-LogMessage -Level Info "Deploying VNet gateway from template..."
$params = @{
    P2S_VPN_Certificate = (Get-AzKeyVaultSecret -VaultName $config.keyVault.Name -Name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText
    Shm_Id = "$($config.id)".ToLower()
    Subnet_Gateway_CIDR = $config.network.vnet.subnets.gateway.cidr
    Subnet_Gateway_Name = $config.network.vnet.subnets.gateway.Name
    Subnet_Identity_CIDR = $config.network.vnet.subnets.identity.cidr
    Subnet_Identity_Name = $config.network.vnet.subnets.identity.Name
    Subnet_Web_CIDR = $config.network.vnet.subnets.web.cidr
    Subnet_Web_Name = $config.network.vnet.subnets.web.Name
    Virtual_Network_Name = $config.network.vnet.Name
    VNET_CIDR = $config.network.vnet.cidr
    VNET_DNS_DC1 = $config.dc.ip
    VNET_DNS_DC2 = $config.dcb.ip
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-vnet-template.json") -Params $params -ResourceGroupName $config.network.vnet.rg


# Create SHM DC resource group if it does not exist
# -------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.dc.rg -Location $config.location


# Retrieve usernames/passwords from the keyvault
# ----------------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.keyVault.name)'..."
$domainAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.domainAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()
$domainAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.domainAdminPassword -DefaultLength 20
$safemodeAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.dc.safemodePasswordSecretName -DefaultLength 20


# Deploy SHM DC from template
# ---------------------------
Add-LogMessage -Level Info "Deploying domain controller (DC) from template..."
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
$params = @{
    Administrator_Password = (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)
    Administrator_User = $domainAdminUsername
    Artifacts_Location = "https://$($config.storage.artifacts.accountName).blob.core.windows.net"
    Artifacts_Location_SAS_Token = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)
    BootDiagnostics_Account_Name = $config.storage.bootdiagnostics.accountName
    DC1_Data_Disk_Size_GB = [int]$config.dc.disks.data.sizeGb
    DC1_Data_Disk_Type = $config.dc.disks.data.type
    DC1_Host_Name = $config.dc.hostname
    DC1_IP_Address = $config.dc.ip
    DC1_Os_Disk_Size_GB = [int]$config.dc.disks.os.sizeGb
    DC1_Os_Disk_Type = $config.dc.disks.os.type
    DC1_VM_Name = $config.dc.vmName
    DC1_VM_Size = $config.dc.vmSize
    DC2_Host_Name = $config.dcb.hostname
    DC2_Data_Disk_Size_GB = [int]$config.dcb.disks.data.sizeGb
    DC2_Data_Disk_Type = $config.dcb.disks.data.type
    DC2_IP_Address = $config.dcb.ip
    DC2_Os_Disk_Size_GB = [int]$config.dcb.disks.os.sizeGb
    DC2_Os_Disk_Type = $config.dcb.disks.os.type
    DC2_VM_Name = $config.dcb.vmName
    DC2_VM_Size = $config.dcb.vmSize
    Domain_Name = $config.domain.fqdn
    Domain_NetBIOS_Name = $config.domain.netbiosName
    External_DNS_Resolver = $config.dc.external_dns_resolver
    SafeMode_Password = (ConvertTo-SecureString $safemodeAdminPassword -AsPlainText -Force)
    Shm_Id = $config.id
    Virtual_Network_Name = $config.network.vnet.Name
    Virtual_Network_Resource_Group = $config.network.vnet.rg
    Virtual_Network_Subnet = $config.network.vnet.subnets.identity.Name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-dc-template.json") -Params $params -ResourceGroupName $config.dc.rg


# Import artifacts from blob storage
# ----------------------------------
Add-LogMessage -Level Info "Importing configuration artifacts for: $($config.dc.vmName)..."
# Get list of blobs in the storage account
$storageContainerName = "shm-configuration-dc"
$blobNames = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context | ForEach-Object { $_.Name }
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
$remoteInstallationDir = "C:\Installation"
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Import_Artifacts.ps1" -Resolve
$params = @{
    remoteDir = "`"$remoteInstallationDir`""
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
# Fetch user details
$userAccounts = $config.users.computerManagers + $config.users.serviceAccounts
foreach ($user in $userAccounts.Keys) {
    $userAccounts[$user]["password"] = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $userAccounts[$user]["passwordSecretName"] -DefaultLength 20
}
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Active_Directory_Configuration.ps1"
$params = @{
    domainAdminUsername = "`"$domainAdminUsername`""
    domainControllerVmName = "`"$($config.dc.vmName)`""
    netbiosName = "`"$($config.domain.netbiosName)`""
    ouBackupPath = "`"C:\Installation\GPOs`""
    sgComputerManagersName = "`"$($config.domain.securityGroups.computerManagers.name)`""
    sgServerAdminsName = "`"$($config.domain.securityGroups.serverAdmins.name)`""
    shmDomainOu = "`"$($config.domain.dn)`""
    shmFdqn = "`"$($config.domain.fqdn)`""
    userAccountsB64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($userAccounts | ConvertTo-Json)))
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params
Write-Output $result.Value


# Configure group policies
# ------------------------
Add-LogMessage -Level Info "Configuring group policies for: $($config.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Configure_Group_Policies.ps1"
$params = @{
    shmFqdn = "`"$($config.domain.fqdn)`""
    serverAdminSgName = "`"$($config.domain.securityGroups.serverAdmins.name)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params
Write-Output $result.Value


# Configure the domain controllers and set their DNS resolution
# -------------------------------------------------------------
foreach ($vmName in ($config.dc.vmName, $config.dcb.vmName)) {
    # Configure DNS to forward requests to the Azure DNS resolver
    $params = @{
        externalDnsResolver = "`"$($config.dc.external_dns_resolver)`""
    }
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Configure_DNS.ps1"
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.dc.rg -Parameter $params
    Write-Output $result.Value

    # Remove custom per-NIC DNS settings
    $nic = Get-AzNetworkInterface -ResourceGroupName $config.dc.rg -Name "${vmName}-NIC"
    $nic.DnsSettings.DnsServers.Clear()
    $nic | Set-AzNetworkInterface

    # Set locale, install updates and reboot
    Add-LogMessage -Level Info "Updating DC VM '$vmName'..."
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.dc.rg
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
