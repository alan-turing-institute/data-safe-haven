param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
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
$config = Get-ShmFullConfig ($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Create resource group if it does not exist
# ------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.nps.rg -Location $config.location


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.keyVault.name)'..."
$shmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()
$domainAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.domainAdminPassword -DefaultLength 20
$npsAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.npsAdminPassword -DefaultLength 20


# Ensure that artifacts resource group, storage account and storage container exist
# ---------------------------------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.storage.artifacts.rg -Location $config.location
$storageAccount = Deploy-StorageAccount -Name $config.storage.artifacts.accountName -ResourceGroupName $config.storage.artifacts.rg -Location $config.location
$storageContainerName = "shm-configuration-nps"
$_ = Deploy-StorageContainer -Name $storageContainerName -StorageAccount $storageAccount


# Upload artifacts
# ----------------
Add-LogMessage -Level Info "Uploading artifacts to storage account '$($config.storage.artifacts.accountName)'..."
Add-LogMessage -Level Info "[ ] Uploading network policy server (NPS) configuration files to blob storage"
$success = $true
foreach ($filePath in $(Get-ChildItem (Join-Path $PSScriptRoot ".." "remote" "create_nps" "artifacts") -Recurse)) {
    $_ = Set-AzStorageBlobContent -Container $storageContainerName -Context $storageAccount.Context -File $filePath -Force
    $success = $success -and $?
}
if ($success) {
    Add-LogMessage -Level Success "Uploaded NPS configuration files"
} else {
    Add-LogMessage -Level Fatal "Failed to upload NPS configuration files!"
}

# Deploy NPS from template
# ------------------------
Add-LogMessage -Level Info "Deploying network policy server (NPS) from template..."
$params = @{
    Administrator_Password = (ConvertTo-SecureString $npsAdminPassword -AsPlainText -Force)
    Administrator_User = $shmAdminUsername
    BootDiagnostics_Account_Name = $config.storage.bootdiagnostics.accountName
    DC_Administrator_Password = (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)
    DC_Administrator_User = $shmAdminUsername
    Domain_Name = $config.domain.fqdn
    NPS_Host_Name = $config.nps.hostname
    NPS_IP_Address = $config.nps.ip
    NPS_VM_Name = $config.nps.vmName
    OU_Path = $config.domain.serviceServerOuPath
    Virtual_Network_Name = $config.network.vnet.name
    Virtual_Network_Resource_Group = $config.network.vnet.rg
    Virtual_Network_Subnet = $config.network.subnets.identity.name
    VM_Size = $config.nps.vmSize
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-nps-template.json") -Params $params -ResourceGroupName $config.nps.rg


# Run configuration script remotely
# ---------------------------------
Add-LogMessage -Level Info "Configuring NPS server '$($config.nps.vmName)'..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_nps" "scripts" "Prepare_NPS_Server.ps1"
$params = @{
    remoteDir = "`"C:\Installation`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -Parameter $params
Write-Output $result.Value


# Import RDG conditional-access-policy settings
# ---------------------------------------------
Add-LogMessage -Level Info "Importing NPS configuration '$($config.nps.vmName)'..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_nps" "scripts" "Import_NPS_Config.ps1"
$blobNames = Get-AzStorageBlob -Container $storageContainerName -Context $storageAccount.Context | ForEach-Object { $_.Name }
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg -AccountName $config.storage.artifacts.accountName
$params = @{
    remoteDir = "`"C:\Installation`""
    pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
    storageAccountName = "`"$($config.storage.artifacts.accountName)`""
    storageContainerName = "`"$storageContainerName`""
    sasToken = "`"$artifactSasToken`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -Parameter $params
Write-Output $result.Value


# Set locale, install updates and reboot
# --------------------------------------
Add-LogMessage -Level Info "Updating NPS VM '$($config.nps.vmName)'..."
Invoke-WindowsConfigureAndUpdate -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
