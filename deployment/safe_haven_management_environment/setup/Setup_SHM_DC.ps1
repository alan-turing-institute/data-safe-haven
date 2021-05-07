param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Setup boot diagnostics resource group and storage account
# ---------------------------------------------------------
# $null = Deploy-ResourceGroup -Name $config.storage.bootdiagnostics.rg -Location $config.location
# $null = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location


# Setup artifacts resource group and storage account
# --------------------------------------------------
# $null = Deploy-ResourceGroup -Name $config.storage.artifacts.rg -Location $config.location
# $storageAccount = Deploy-StorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -Location $config.location


# Create blob storage containers
# ------------------------------
# Add-LogMessage -Level Info "Ensuring that blob storage containers exist..."
# foreach ($containerName in ("shm-dsc-dc", "shm-configuration-dc", "sre-rds-sh-packages")) {
#     $null = Deploy-StorageContainer -Name $containerName -StorageAccount $storageAccount
# }


# Upload artifacts
# ----------------
# Add-LogMessage -Level Info "Uploading artifacts to storage account '$($config.storage.artifacts.accountName)'..."
# # Upload DSC scripts
# Add-LogMessage -Level Info "[ ] Uploading desired state configuration (DSC) files to blob storage"
# $null = Set-AzStorageBlobContent -Container "shm-dsc-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-setup-scripts" "CreateADPDC.zip") -Force
# $success = $?
# $null = Set-AzStorageBlobContent -Container "shm-dsc-dc" -Context $storageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc2-setup-scripts" "CreateADBDC.zip") -Force
# $success = $success -and $?
# if ($success) {
#     Add-LogMessage -Level Success "Uploaded desired state configuration (DSC) files"
# } else {
#     Add-LogMessage -Level Fatal "Failed to upload desired state configuration (DSC) files!"
# }
# Upload artifacts for configuring the DC
# Add-LogMessage -Level Info "[ ] Uploading domain controller (DC) configuration files to blob storage"
# $success = $true
# foreach ($filePath in $(Get-ChildItem -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-configuration"))) {
#     if ($($filePath | Split-Path -Leaf) -eq "Disconnect_AD.template.ps1") {
#         # Expand the AD disconnection template before uploading
#         $adScriptLocalFilePath = (New-TemporaryFile).FullName
#         (Get-Content $filePath -Raw).Replace("<shm-fqdn>", $config.domain.fqdn) | Out-File $adScriptLocalFilePath
#         $null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -Blob "Disconnect_AD.ps1" -File $adScriptLocalFilePath -Force
#         $null = Remove-Item $adScriptLocalFilePath
#     } else {
#         # $null = Set-AzStorageBlobContent -Container "shm-configuration-dc" -Context $storageAccount.Context -File $filePath -Force
#     }
#     $success = $success -and $?
# }
# if ($success) {
#     Add-LogMessage -Level Success "Uploaded domain controller (DC) configuration files"
# } else {
#     Add-LogMessage -Level Fatal "Failed to upload domain controller (DC) configuration files!"
# }
# Upload Windows package installers
# Add-LogMessage -Level Info "[ ] Uploading Windows package installers to blob storage"
# $success = $true
# # Chrome
# $filename = "GoogleChromeStandaloneEnterprise64.msi"
# Start-AzStorageBlobCopy -AbsoluteUri "http://dl.google.com/edgedl/chrome/install/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "GoogleChrome_x64.msi" -DestContext $storageAccount.Context -Force
# $success = $success -and $?
# PuTTY
# $baseUri = "https://the.earth.li/~sgtatham/putty/latest/w64/"
# $httpContent = Invoke-WebRequest -Uri $baseUri
# $filename = $httpContent.Links | Where-Object { $_.href -like "*installer.msi" } | ForEach-Object { $_.href } | Select-Object -First 1
# $version = ($filename -split "-")[2]
# Start-AzStorageBlobCopy -AbsoluteUri "$($baseUri.Replace('latest', $version))/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "PuTTY_x64.msi" -DestContext $storageAccount.Context -Force
# $success = $success -and $?
# if ($success) {
#     Add-LogMessage -Level Success "Uploaded Windows package installers"
# } else {
#     Add-LogMessage -Level Fatal "Failed to upload Windows package installers!"
# }


# Create SHM DC resource group if it does not exist
# -------------------------------------------------
# $null = Deploy-ResourceGroup -Name $config.dc.rg -Location $config.location


# Retrieve usernames/passwords from the Key Vault
# -----------------------------------------------
# Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.keyVault.name)'..."
$domainAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.domainAdminUsername -DefaultValue "domain$($config.id)admin".ToLower() -AsPlaintext
# $domainAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.domainAdminPassword -DefaultLength 20 -AsPlaintext
# $safemodeAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.dc.safemodePasswordSecretName -DefaultLength 20 -AsPlaintext


# Deploy SHM DC from template
# ---------------------------
# Add-LogMessage -Level Info "Deploying domain controller (DC) from template..."
# $artifactSasToken = New-ReadOnlyStorageAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
# $params = @{
#     Administrator_Password         = (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)
#     Administrator_User             = $domainAdminUsername
#     Artifacts_Location             = "https://$($config.storage.artifacts.accountName).blob.core.windows.net"
#     Artifacts_Location_SAS_Token   = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)
#     BootDiagnostics_Account_Name   = $config.storage.bootdiagnostics.accountName
#     DC1_Data_Disk_Size_GB          = [int]$config.dc.disks.data.sizeGb
#     DC1_Data_Disk_Type             = $config.dc.disks.data.type
#     DC1_Host_Name                  = $config.dc.hostname
#     DC1_IP_Address                 = $config.dc.ip
#     DC1_Os_Disk_Size_GB            = [int]$config.dc.disks.os.sizeGb
#     DC1_Os_Disk_Type               = $config.dc.disks.os.type
#     DC1_VM_Name                    = $config.dc.vmName
#     DC1_VM_Size                    = $config.dc.vmSize
#     DC2_Host_Name                  = $config.dcb.hostname
#     DC2_Data_Disk_Size_GB          = [int]$config.dcb.disks.data.sizeGb
#     DC2_Data_Disk_Type             = $config.dcb.disks.data.type
#     DC2_IP_Address                 = $config.dcb.ip
#     DC2_Os_Disk_Size_GB            = [int]$config.dcb.disks.os.sizeGb
#     DC2_Os_Disk_Type               = $config.dcb.disks.os.type
#     DC2_VM_Name                    = $config.dcb.vmName
#     DC2_VM_Size                    = $config.dcb.vmSize
#     Domain_Name                    = $config.domain.fqdn
#     Domain_NetBIOS_Name            = $config.domain.netbiosName
#     External_DNS_Resolver          = $config.dc.external_dns_resolver
#     SafeMode_Password              = (ConvertTo-SecureString $safemodeAdminPassword -AsPlainText -Force)
#     Shm_Id                         = $config.id
#     Virtual_Network_Name           = $config.network.vnet.name
#     Virtual_Network_Resource_Group = $config.network.vnet.rg
#     Virtual_Network_Subnet         = $config.network.vnet.subnets.identity.name
# }
# Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-dc-template.json") -Params $params -ResourceGroupName $config.dc.rg

$storageAccount = Get-AzStorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -ErrorVariable notExists -ErrorAction SilentlyContinue

# Import artifacts from blob storage
# ----------------------------------
Add-LogMessage -Level Info "Importing configuration artifacts for: $($config.dc.vmName)..."
# Get list of blobs in the storage account
$storageContainerName = "shm-configuration-dc"
$blobNames = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context | ForEach-Object { $_.Name }
$artifactSasToken = New-ReadOnlyStorageAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
# Run remote script
$params = @{
    blobNameArrayB64     = $blobNames | ConvertTo-Json | ConvertTo-Base64
    downloadDir          = $config.dc.installationDirectory
    sasTokenB64          = $artifactSasToken | ConvertTo-Base64
    storageAccountName   = $config.storage.artifacts.accountName
    storageContainerName = $storageContainerName
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Import_Artifacts.ps1" -Resolve
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params


# # Configure Active Directory remotely
# # -----------------------------------
# Add-LogMessage -Level Info "Configuring Active Directory for: $($config.dc.vmName)..."
# # Fetch user and OU details


# # Run remote script
# $scriptTemplate = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Active_Directory_Configuration_template.ps1" | Get-Item | Get-Content -Raw
# $script = $scriptTemplate.Replace("<ou-database-servers-name>", $config.domain.ous.databaseServers.name).
#                           Replace("<ou-identity-servers-name>", $config.domain.ous.identityServers.name).
#                           Replace("<ou-linux-servers-name>", $config.domain.ous.linuxServers.name).
#                           Replace("<ou-rds-gateway-servers-name>", $config.domain.ous.rdsGatewayServers.name).
#                           Replace("<ou-rds-session-servers-name>", $config.domain.ous.rdsSessionServers.name).
#                           Replace("<ou-research-users-name>", $config.domain.ous.researchUsers.name).
#                           Replace("<ou-security-groups-name>", $config.domain.ous.securityGroups.name).
#                           Replace("<ou-service-accounts-name>", $config.domain.ous.serviceAccounts.name)


$userAccounts = $config.users.computerManagers + $config.users.serviceAccounts
foreach ($user in $userAccounts.Keys) {
    $userAccounts[$user]["password"] = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $userAccounts[$user]["passwordSecretName"] -DefaultLength 20 -AsPlaintext
}

$params = @{
    domainAdminUsername    = $domainAdminUsername
    domainControllerVmName = $config.dc.vmName
    domainOuBase           = $config.domain.dn
    gpoBackupPath          = "$($config.dc.installationDirectory)\GPOs"
    netbiosName            = $config.domain.netbiosName
    shmFdqn                = $config.domain.fqdn
    userAccountsB64        = $userAccounts | ConvertTo-Json | ConvertTo-Base64
    securityGroupsB64      = $config.domain.securityGroups | ConvertTo-Json | ConvertTo-Base64
}
$null = Invoke-RemoteScript -Shell "PowerShell" -Script $script -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params


# Configure group policies
# ------------------------
Add-LogMessage -Level Info "Configuring group policies for: $($config.dc.vmName)..."
$params = @{
    shmFqdn           = $config.domain.fqdn
    serverAdminSgName = $config.domain.securityGroups.serverAdmins.name
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Configure_Group_Policies.ps1"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params


# Configure the domain controllers and set their DNS resolution
# -------------------------------------------------------------
foreach ($vmName in ($config.dc.vmName, $config.dcb.vmName)) {
    # Configure DNS to forward requests to the Azure DNS resolver
    $params = @{
        ExternalDnsResolver = $config.dc.external_dns_resolver
        IdentitySubnetCidr  = $config.network.vnet.subnets.identity.cidr
    }
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Configure_DNS.ps1"
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.dc.rg -Parameter $params

    # Remove custom per-NIC DNS settings
    $networkCard = Get-AzNetworkInterface -ResourceGroupName $config.dc.rg -Name "${vmName}-NIC"
    $networkCard.DnsSettings.DnsServers.Clear()
    $null = $networkCard | Set-AzNetworkInterface

    # Set locale, install updates and reboot
    Add-LogMessage -Level Info "Updating DC VM '$vmName'..."
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.dc.rg -TimeZone $config.time.timezone.windows -NtpServer $config.time.ntp.poolFqdn -AdditionalPowershellModules "MSOnline"
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
