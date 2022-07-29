param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.DataProtection -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
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
                                            -Vaultname $config.sre.backup.vault.name `
                                            -PolicyName $config.sre.backup.blob.policy_name `
                                            -DataSourcetype 'blob'

# Assign permissions required for backup to the Vault's managed identity
$VaultIdentityId = $Vault.IdentityPrincipalId
$ResourceType = "Microsoft.Storage/storageAccounts"
$RoleDefinition = "Storage Account Backup Contributor"

$PersistentStorageAccount = Get-AzStorageAccount -ResourceGroupName $config.shm.storage.persistentdata.rg `
                                                 -Name $config.sre.storage.persistentdata.account.name

Add-LogMessage -Level Info "Ensuring that role assignment(s) for blob backup exists..."
$Assignment = Get-AzRoleAssignment -ObjectId $VaultIdentityId `
                                   -RoleDefinitionName $RoleDefinition `
                                   -ResourceGroupName $config.shm.storage.persistentdata.rg `
                                   -ResourceType $ResourceType `
                                   -ResourceName $config.sre.storage.persistentdata.account.name
if ($Assignment -eq $null) {
    Add-LogMessage -Level Info "[ ] Creating role assignment(s) for blob backup"
    $null = New-AzRoleAssignment -ObjectId $VaultIdentityId `
                                 -RoleDefinitionName RoleDefinition `
                                 -ResourceGroupName $config.shm.storage.persistentdata.rg `
                                 -ResourceType $ResourceType `
                                 -ResourceName $config.sre.storage.persistentdata.account.name
    if ($?) {
        Add-LogMessage -Level Success "Successfully created role assignment(s)"
    } else {
        Add-LogMessage -Level Fatal "Failed to create role assignment(s)"
    }
} else {
    Add-LogMessage -Level InfoSuccess "Role assignment(s) already exists"
}

# Create blob backup instance
$Instance = Initialize-AzDataProtectionBackupInstance -DataSourceType  "AzureBlob" `
                                                      -DataSourceLocation $PersistentStorageAccount.Location `
                                                      -PolicyId $Policy.Id `
                                                      -DataSourceId $PersistentStorageAccount.Id
New-AzDataProtectionBackupInstance -ResourceGroupName $config.sre.backup.rg `
                                   -VaultName $config.sre.backup.vault.name `
                                   -BackupInstance $Instance
