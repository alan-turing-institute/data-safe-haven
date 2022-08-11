param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module $PSScriptRoot/../../common/AzureDataProtection -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop

# Deploy backup resource group
$null = Deploy-ResourceGroup -Name $config.sre.backup.rg -Location $config.shm.location

# Deploy data protection backup vault
$Vault = Deploy-DataProtectionBackupVault -ResourceGroupName $config.sre.backup.rg `
                                         -VaultName $config.sre.backup.vault.name `
                                         -Location $config.sre.location

# Create blob backup policy
# This enforces the default policy for blobs
$Policy = Deploy-DataProtectionBackupPolicy -ResourceGroupName $config.sre.backup.rg `
                                            -VaultName $config.sre.backup.vault.name `
                                            -PolicyName $config.sre.backup.blob.policy_name `
                                            -DataSourceType 'blob'

# Assign permissions required for backup to the Vault's managed identity
$PersistentStorageAccount = Get-AzStorageAccount -ResourceGroupName $config.shm.storage.persistentdata.rg -Name $config.sre.storage.persistentdata.account.name
$null = Deploy-RoleAssignment -ObjectId $Vault.IdentityPrincipalId `
                              -ResourceGroupName $PersistentStorageAccount.ResourceGroupName `
                              -ResourceType "Microsoft.Storage/storageAccounts" `
                              -ResourceName $PersistentStorageAccount.StorageAccountName `
                              -RoleDefinitionName "Storage Account Backup Contributor"

# Create blob backup instance
$Instance = Deploy-StorageAccountBackupInstance -BackupPolicyId $Policy.Id `
                                                -ResourceGroupName $config.sre.backup.rg `
                                                -StorageAccount $PersistentStorageAccount `
                                                -VaultName $Vault.Name
