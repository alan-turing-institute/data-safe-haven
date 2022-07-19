param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop
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


# Create resource group if it does not exist
# ------------------------------------------
$null = Deploy-ResourceGroup -Name $config.nps.rg -Location $config.location


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.keyVault.name)'..."
$domainJoinPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.users.computerManagers.identityServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower() -AsPlaintext
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.nps.adminPasswordSecretName -DefaultLength 20 -AsPlaintext


# Ensure that artifacts resource group, storage account and storage container exist
# ---------------------------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.storage.artifacts.rg -Location $config.location
$storageAccount = Deploy-StorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -Location $config.location
$storageContainerDscName = "shm-desired-state"
$storageContainerArtifactsName = "shm-nps-artifacts"
$null = Deploy-StorageContainer -Name $storageContainerArtifactsName -StorageAccount $storageAccount


# Upload artifacts
# ----------------
Add-LogMessage -Level Info "Uploading NPS artifacts to storage account '$($config.storage.artifacts.accountName)'..."
try {
    $success = $true
    # Desired state
    $dscPath = Join-Path $PSScriptRoot ".." "desired_state_configuration"
    $null = Publish-AzVMDscConfiguration -ConfigurationPath (Join-Path $dscPath "NPSDesiredState.ps1") `
                                        -ContainerName $storageContainerDscName `
                                        -Force `
                                        -ResourceGroupName $config.storage.artifacts.rg `
                                        -SkipDependencyDetection `
                                        -StorageAccountName $config.storage.artifacts.accountName
    $success = $success -and $?
    # Local artifacts
    foreach ($filePath in $(Get-ChildItem (Join-Path $dscPath "npsArtifacts") -Recurse)) {
        $null = Set-AzStorageBlobContent -Container $storageContainerArtifactsName -Context $storageAccount.Context -File $filePath -Force
        $success = $success -and $?
    }
    # Remote artifacts
    $null = Set-AzureStorageBlobFromUri -FileUri "https://raw.githubusercontent.com/Azure-Samples/azure-mfa-nps-extension-health-check/master/MFA_NPS_Troubleshooter.ps1" -StorageContainer $storageContainerArtifactsName -StorageContext $storageAccount.Context
    $null = Set-AzureStorageBlobFromUri -FileUri "https://download.microsoft.com/download/B/F/F/BFFB4F12-9C09-4DBC-A4AF-08E51875EEA9/NpsExtnForAzureMfaInstaller.exe" -StorageContainer $storageContainerArtifactsName -StorageContext $storageAccount.Context
    if (-not $success) { throw }
    Add-LogMessage -Level Success "Uploaded NPS artifacts to storage account '$($config.storage.artifacts.accountName)'"
} catch {
    Add-LogMessage -Level Fatal "Failed to upload NPS artifacts to storage account '$($config.storage.artifacts.accountName)'!"
}


# Deploy NPS from template
# ------------------------
Add-LogMessage -Level Info "Deploying network policy server (NPS) from template..."
$params = @{
    administratorPassword           = (ConvertTo-SecureString $vmAdminPassword -AsPlainText -Force)
    administratorUsername           = $vmAdminUsername
    bootDiagnosticsAccountName      = $config.storage.bootdiagnostics.accountName
    domainJoinOuPath                = $config.domain.ous.identityServers.path
    domainJoinPassword              = (ConvertTo-SecureString $domainJoinPassword -AsPlainText -Force)
    domainJoinUser                  = $config.users.computerManagers.identityServers.samAccountName
    domainName                      = $config.domain.fqdn
    virtualNetworkName              = $config.network.vnet.name
    virtualNetworkResourceGroupName = $config.network.vnet.rg
    virtualNetworkSubnetName        = $config.network.vnet.subnets.identity.name
    vmHostName                      = $config.nps.hostname
    vmName                          = $config.nps.vmName
    vmOsDiskSizeGb                  = [int]$config.nps.disks.os.sizeGb
    vmOsDiskType                    = $config.nps.disks.os.type
    vmPrivateIpAddress              = $config.nps.ip
    vmSize                          = $config.nps.vmSize
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-nps-template.json") -TemplateParameters $params -ResourceGroupName $config.nps.rg


# Apply SHM NPS desired state
# ---------------------------
Add-LogMessage -Level Info "Installing desired state prerequisites on NPS..."
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath (Join-Path $dscPath "NPSBootstrap.ps1") -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -SuppressOutput
$params = @{
    ArtifactsBlobNamesB64         = Get-AzStorageBlob -Container $storageContainerArtifactsName -Context $storageAccount.Context | ForEach-Object { $_.Name } | ConvertTo-Json -Depth 99 | ConvertTo-Base64
    ArtifactsBlobSasTokenB64      = (New-ReadOnlyStorageAccountSasToken -SubscriptionName $config.subscriptionName -ResourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName) | ConvertTo-Base64
    ArtifactsStorageAccountName   = $config.storage.artifacts.accountName
    ArtifactsStorageContainerName = $storageContainerArtifactsName
    ArtifactsTargetDirectory      = $config.nps.installationDirectory
}
$null = Invoke-AzureVmDesiredState -ArchiveBlobName "NPSDesiredState.ps1.zip" `
                                   -ArchiveContainerName $storageContainerDscName `
                                   -ArchiveResourceGroupName $config.storage.artifacts.rg `
                                   -ArchiveStorageAccountName $config.storage.artifacts.accountName `
                                   -ConfigurationName "ConfigureNetworkPolicyServer" `
                                   -ConfigurationParameters $params `
                                   -VmLocation $config.location `
                                   -VmName $config.nps.vmName `
                                   -VmResourceGroupName $config.nps.rg


# Set locale, install updates and reboot
# --------------------------------------
Add-LogMessage -Level Info "Updating NPS VM '$($config.nps.vmName)'..."
Invoke-WindowsConfiguration -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -TimeZone $config.time.timezone.windows -NtpServer ($config.time.ntp.serverAddresses)[0]


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
