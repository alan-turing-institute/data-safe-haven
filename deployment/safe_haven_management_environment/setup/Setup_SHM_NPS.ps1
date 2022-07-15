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


# Create resource group if it does not exist
# ------------------------------------------
$null = Deploy-ResourceGroup -Name $config.nps.rg -Location $config.location


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.keyVault.name)'..."
$domainJoinUsername = $config.users.computerManagers.identityServers.samAccountName
$domainJoinPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.users.computerManagers.identityServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower() -AsPlaintext
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.nps.adminPasswordSecretName -DefaultLength 20 -AsPlaintext


# Ensure that artifacts resource group, storage account and storage container exist
# ---------------------------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.storage.artifacts.rg -Location $config.location
$storageAccount = Deploy-StorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -Location $config.location
$storageContainerName = "shm-configuration-nps"
$null = Deploy-StorageContainer -Name $storageContainerName -StorageAccount $storageAccount


# Upload artifacts
# ----------------
Add-LogMessage -Level Info "Uploading artifacts to storage account '$($config.storage.artifacts.accountName)'..."
Add-LogMessage -Level Info "[ ] Uploading network policy server (NPS) configuration files to blob storage"
$success = $true
foreach ($filePath in $(Get-ChildItem (Join-Path $PSScriptRoot ".." "remote" "create_nps" "artifacts") -Recurse)) {
    $null = Set-AzStorageBlobContent -Container $storageContainerName -Context $storageAccount.Context -File $filePath -Force
    $success = $success -and $?
}
if ($success) {
    Add-LogMessage -Level Success "Uploaded NPS configuration files"
} else {
    Add-LogMessage -Level Fatal "Failed to upload NPS configuration files!"
}
Add-LogMessage -Level Info "[ ] Uploading MFA NPS troubleshooting script to blob storage"
Start-AzStorageBlobCopy -AbsoluteUri https://raw.githubusercontent.com/Azure-Samples/azure-mfa-nps-extension-health-check/master/MFA_NPS_Troubleshooter.ps1 -DestContainer $storageContainerName -DestBlob "MFA_NPS_Troubleshooter.ps1" -DestContext $storageAccount.Context -Force
if ($?) {
    Add-LogMessage -Level Success "Uploaded MFA NPS troubleshooting script"
} else {
    Add-LogMessage -Level Fatal "Failed to upload MFA NPS troubleshooting script!"
}


# Deploy NPS from template
# ------------------------
Add-LogMessage -Level Info "Deploying network policy server (NPS) from template..."
# NB. We do not currently use the dedicated service-servers computer management user.
# This will need some deeper thought about which OU each VM should belong to.
$params = @{
    administratorPassword           = (ConvertTo-SecureString $vmAdminPassword -AsPlainText -Force)
    administratorUsername           = $vmAdminUsername
    bootDiagnosticsAccountName      = $config.storage.bootdiagnostics.accountName
    domainJoinOuPath                = $config.domain.ous.identityServers.path
    domainJoinPassword              = (ConvertTo-SecureString $domainJoinPassword -AsPlainText -Force)
    domainJoinUser                  = $domainJoinUsername
    domainName                      = $config.domain.fqdn
    npsHostName                     = $config.nps.hostname
    npsIpAddress                    = $config.nps.ip
    npsOsDiskSizeGb                 = [int]$config.nps.disks.os.sizeGb
    npsOsDiskType                   = $config.nps.disks.os.type
    npsVmName                       = $config.nps.vmName
    npsVmSize                       = $config.nps.vmSize
    virtualNetworkName              = $config.network.vnet.name
    virtualNetworkResourceGroupName = $config.network.vnet.rg
    virtualNetworkSubnetName        = $config.network.vnet.subnets.identity.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-nps-template.json") -Params $params -ResourceGroupName $config.nps.rg


# Run configuration script remotely
# ---------------------------------
Add-LogMessage -Level Info "Configuring NPS server '$($config.nps.vmName)'..."
$params = @{
    installationDir = $config.nps.installationDirectory
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_nps" "scripts" "Prepare_NPS_Server.ps1"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -Parameter $params


# Import conditional-access-policy settings
# -----------------------------------------
Add-LogMessage -Level Info "Copying NPS artifacts to '$($config.nps.vmName)'..."
$blobNames = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context | ForEach-Object { $_.Name }
$artifactSasToken = New-ReadOnlyStorageAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
$params = @{
    blobNameArrayB64     = $blobNames | ConvertTo-Json -Depth 99 | ConvertTo-Base64
    installationDir      = $config.nps.installationDirectory
    sasTokenB64          = $artifactSasToken | ConvertTo-Base64
    storageAccountName   = $config.storage.artifacts.accountName
    storageContainerName = $storageContainerName
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_nps" "scripts" "Import_NPS_Config.ps1"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -Parameter $params


# Set locale, install updates and reboot
# --------------------------------------
Add-LogMessage -Level Info "Updating NPS VM '$($config.nps.vmName)'..."
Invoke-WindowsConfigureAndUpdate -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -TimeZone $config.time.timezone.windows -NtpServer ($config.time.ntp.serverAddresses)[0] -AdditionalPowershellModules "MSOnline"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
