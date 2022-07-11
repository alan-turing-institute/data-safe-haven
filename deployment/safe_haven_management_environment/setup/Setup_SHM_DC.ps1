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
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


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
$storageContainerDcConfigName = "shm-configuration-dc"
$storageContainerDcDscName = "shm-dsc-dc"
foreach ($containerName in ($storageContainerDcDscName, $storageContainerDcConfigName, "sre-rds-sh-packages")) {
    $null = Deploy-StorageContainer -Name $containerName -StorageAccount $storageAccount
}


# Upload DSC scripts
# ------------------
Add-LogMessage -Level Info "[ ] Uploading desired state configuration (DSC) files to storage account '$($storageAccount.Name)'..."
$dc1DscPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-desiredstate"
$null = Publish-AzVMDscConfiguration -ConfigurationPath (Join-Path $dc1DscPath "CreatePrimaryDomainController.ps1") `
                                     -ContainerName $storageContainerDcDscName `
                                     -Force `
                                     -ResourceGroupName $config.storage.artifacts.rg `
                                     -SkipDependencyDetection `
                                     -StorageAccountName $config.storage.artifacts.accountName
$success = $?
$dc2DscPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc2-desiredstate"
$null = Publish-AzVMDscConfiguration -ConfigurationPath (Join-Path $dc2DscPath "CreateSecondaryDomainController.ps1") `
                                     -ContainerName $storageContainerDcDscName `
                                     -Force `
                                     -ResourceGroupName $config.storage.artifacts.rg `
                                     -SkipDependencyDetection `
                                     -StorageAccountName $config.storage.artifacts.accountName
$success = $success -and $?
if ($success) {
    Add-LogMessage -Level Success "Uploaded desired state configuration (DSC) files"
} else {
    Add-LogMessage -Level Fatal "Failed to upload desired state configuration (DSC) files!"
}


# Upload artifacts for configuring the DC
# ---------------------------------------
Add-LogMessage -Level Info "[ ] Uploading domain controller (DC) configuration files to storage account '$($storageAccount.Name)'..."
$success = $true
foreach ($filePath in $(Get-ChildItem -File (Join-Path $PSScriptRoot ".." "remote" "create_dc" "artifacts" "shm-dc1-uploads"))) {
    if ($($filePath | Split-Path -Leaf) -eq "Disconnect_AD.mustache.ps1") {
        # Expand the AD disconnection template before uploading
        $adScriptLocalFilePath = (New-TemporaryFile).FullName
        Expand-MustacheTemplate -Template $(Get-Content $filePath -Raw) -Parameters $config | Out-File $adScriptLocalFilePath
        $null = Set-AzStorageBlobContent -Container $storageContainerDcConfigName -Context $storageAccount.Context -Blob "Disconnect_AD.ps1" -File $adScriptLocalFilePath -Force
        $null = Remove-Item $adScriptLocalFilePath
    } else {
        $null = Set-AzStorageBlobContent -Container $storageContainerDcConfigName -Context $storageAccount.Context -File $filePath -Force
    }
    $success = $success -and $?
}
if ($success) {
    Add-LogMessage -Level Success "Uploaded domain controller (DC) configuration files"
} else {
    Add-LogMessage -Level Fatal "Failed to upload domain controller (DC) configuration files!"
}


# Upload Windows package installers
# ---------------------------------
Add-LogMessage -Level Info "[ ] Uploading Windows package installers to storage account '$($storageAccount.Name)'..."
$success = $true
# AzureADConnect
$filename = "AzureADConnect.msi"
Start-AzStorageBlobCopy -AbsoluteUri "https://download.microsoft.com/download/B/0/0/B00291D0-5A83-4DE7-86F5-980BC00DE05A/$filename" -DestContainer "shm-configuration-dc" -DestBlob $filename -DestContext $storageAccount.Context -Force
$success = $success -and $?
# Chrome
$filename = "GoogleChromeStandaloneEnterprise64.msi"
Start-AzStorageBlobCopy -AbsoluteUri "http://dl.google.com/edgedl/chrome/install/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "GoogleChrome_x64.msi" -DestContext $storageAccount.Context -Force
$success = $success -and $?
# PuTTY
$baseUri = "https://the.earth.li/~sgtatham/putty/latest/w64/"
$httpContent = Invoke-WebRequest -Uri $baseUri
$filename = $httpContent.Links | Where-Object { $_.href -like "*installer.msi" } | ForEach-Object { $_.href } | Select-Object -First 1
$version = ($filename -split "-")[2]
Start-AzStorageBlobCopy -AbsoluteUri "$($baseUri.Replace('latest', $version))/$filename" -DestContainer "sre-rds-sh-packages" -DestBlob "PuTTY_x64.msi" -DestContext $storageAccount.Context -Force
$success = $success -and $?
if ($success) {
    Add-LogMessage -Level Success "Uploaded Windows package installers"
} else {
    Add-LogMessage -Level Fatal "Failed to upload Windows package installers!"
}


# Create SHM DC resource group if it does not exist
# -------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.dc.rg -Location $config.location


# Retrieve usernames/passwords from the Key Vault
# -----------------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.keyVault.name)'..."
$domainAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.domainAdminUsername -DefaultValue "domain$($config.id)admin".ToLower() -AsPlaintext
$domainAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.domainAdminPassword -DefaultLength 20 -AsPlaintext
$safemodeAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.dc.safemodePasswordSecretName -DefaultLength 20 -AsPlaintext


# Deploy SHM DC from template
# ---------------------------
Add-LogMessage -Level Info "Deploying domain controllers from template..."
$params = @{
    administratorPassword           = (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)
    administratorUser               = $domainAdminUsername
    bootDiagnosticsAccountName      = $config.storage.bootdiagnostics.accountName
    dc1HostName                     = $config.dc.hostname
    dc1IpAddress                    = $config.dc.ip
    dc1OsDiskSizeGb                 = [int]$config.dc.disks.os.sizeGb
    dc1OsDiskType                   = $config.dc.disks.os.type
    dc1VmName                       = $config.dc.vmName
    dc1VmSize                       = $config.dc.vmSize
    dc2HostName                     = $config.dcb.hostname
    dc2IpAddress                    = $config.dcb.ip
    dc2OsDiskSizeGb                 = [int]$config.dcb.disks.os.sizeGb
    dc2OsDiskType                   = $config.dcb.disks.os.type
    dc2VmName                       = $config.dcb.vmName
    dc2VmSize                       = $config.dcb.vmSize
    externalDnsResolverIpAddress    = $config.dc.external_dns_resolver
    shmId                           = $config.id
    virtualNetworkName              = $config.network.vnet.name
    virtualNetworkResourceGroupName = $config.network.vnet.rg
    virtualNetworkSubnetName        = $config.network.vnet.subnets.identity.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-dc-template.json") -Params $params -ResourceGroupName $config.dc.rg


# Apply SHM DC desired state
# --------------------------
$domainAdminCredentials = (New-Object System.Management.Automation.PSCredential ($domainAdminUsername, $(ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)))
$safeModeCredentials = (New-Object System.Management.Automation.PSCredential ($domainAdminUsername, $(ConvertTo-SecureString $safemodeAdminPassword -AsPlainText -Force)))
# DC1
Add-LogMessage -Level Info "Applying desired state configuration to DC1..."
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath (Join-Path $dc1DscPath "dependencies.ps1") -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg
$ds1ConfigurationArguments = @{
    AdministratorCredentials = $domainAdminCredentials
    DomainName               = $config.domain.fqdn
    DomainNetBIOSName        = $config.domain.netbiosName
    SafeModeCredentials      = $safeModeCredentials
}
Set-AzVMDscExtension -ArchiveBlobName "CreatePrimaryDomainController.ps1.zip" `
                     -ArchiveContainerName $storageContainerDcDscName `
                     -ArchiveResourceGroupName $config.storage.artifacts.rg `
                     -ArchiveStorageAccountName $config.storage.artifacts.accountName `
                     -ConfigurationArgument $ds1ConfigurationArguments `
                     -ConfigurationName "CreatePrimaryDomainController" `
                     -Location $config.location `
                     -ResourceGroupName $config.dc.rg `
                     -Version "2.77" `
                     -VMName $config.dc.vmName
# DC2
Add-LogMessage -Level Info "Applying desired state configuration to DC2..."
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath (Join-Path $dc2DscPath "dependencies.ps1") -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg
$ds2ConfigurationArguments = @{
    AdministratorCredentials = $domainAdminCredentials
    DNSServer                = $config.dc.ip
    DomainName               = $config.domain.fqdn
    SafeModeCredentials      = $safeModeCredentials
}
Set-AzVMDscExtension -ArchiveBlobName "CreateSecondaryDomainController.ps1.zip" `
                     -ArchiveContainerName $storageContainerDcDscName `
                     -ArchiveResourceGroupName $config.storage.artifacts.rg `
                     -ArchiveStorageAccountName $config.storage.artifacts.accountName `
                     -ConfigurationArgument $ds2ConfigurationArguments `
                     -ConfigurationName "CreateSecondaryDomainController" `
                     -Location $config.location `
                     -ResourceGroupName $config.dc.rg `
                     -Version "2.77" `
                     -VMName $config.dc.vmName


# Import artifacts from blob storage
# ----------------------------------
Add-LogMessage -Level Info "Importing configuration artifacts for: $($config.dc.vmName)..."
# Get list of blobs in the storage account
$blobNames = Get-AzStorageBlob -Container $storageContainerDcConfigName -Context $storageAccount.Context | ForEach-Object { $_.Name }
$artifactSasToken = New-ReadOnlyStorageAccountSasToken -SubscriptionName $config.subscriptionName -ResourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
# Run remote script
$params = @{
    blobNameArrayB64     = $blobNames | ConvertTo-Json -Depth 99 | ConvertTo-Base64
    sasTokenB64          = $artifactSasToken | ConvertTo-Base64
    storageAccountName   = $config.storage.artifacts.accountName
    storageContainerName = $storageContainerDcConfigName
    targetDirectory      = $config.dc.installationDirectory
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Import_Artifacts.ps1" -Resolve
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params


# Configure Active Directory remotely
# -----------------------------------
Add-LogMessage -Level Info "Configuring Active Directory for: $($config.dc.vmName)..."
# Fetch user and OU details
$userAccounts = $config.users.computerManagers + $config.users.serviceAccounts
foreach ($user in $userAccounts.Keys) {
    $userAccounts[$user]["password"] = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $userAccounts[$user]["passwordSecretName"] -DefaultLength 20 -AsPlaintext
}
# Run remote script
$params = @{
    domainAdminUsername    = $domainAdminUsername
    domainControllerVmName = $config.dc.vmName
    domainOuBase           = $config.domain.dn
    gpoBackupPath          = "$($config.dc.installationDirectory)\GPOs"
    netbiosName            = $config.domain.netbiosName
    shmFdqn                = $config.domain.fqdn
    userAccountsB64        = $userAccounts | ConvertTo-Json -Depth 99 | ConvertTo-Base64
    securityGroupsB64      = $config.domain.securityGroups | ConvertTo-Json -Depth 99 | ConvertTo-Base64
}
$scriptTemplate = Join-Path $PSScriptRoot ".." "remote" "create_dc" "scripts" "Configure_Active_Directory.mustache.ps1" | Get-Item | Get-Content -Raw
$null = Invoke-RemoteScript -Shell "PowerShell" -Script (Expand-MustacheTemplate -Template $scriptTemplate -Parameters $config) -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg -Parameter $params


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
        ExternalDnsResolver = $config.dc.externalDnsResolverIpAddress
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
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.dc.rg -TimeZone $config.time.timezone.windows -NtpServer ($config.time.ntp.serverFqdns)[0] -AdditionalPowershellModules "MSOnline"
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
