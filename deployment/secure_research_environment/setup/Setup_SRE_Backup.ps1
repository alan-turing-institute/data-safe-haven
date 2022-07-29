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
Deploy-DataProtectionBackupPolicy -ResourceGroupName $config.sre.backup.rg `
                                  -Vaultname $config.sre.backup.vault.name `
                                  -PolicyName $config.sre.backup.blob.policy_name `
                                  -DataSourcetype 'blob'

# Assign permissions required for backup to the Vault's managed identity
$VaultIdentityId = $Vault.IdentityPrincipalId

Add-LogMessage -Level Info "Ensuring that role assignment(s) for blob backup exists..."
$Assignment = Get-AzRoleAssignment -ObjectId $VaultIdentityId `
                     -RoleDefinitionName "Storage Account Backup Contributor" `
                     -ResourceGroupName $config.sre.storage.rg
if ($Assignment -eq $null) {
    Add-LogMessage -Level Info "[ ] Creating role assignment(s) for blob backup"
    New-AzRoleAssignment -ObjectId $VaultIdentityId `
                         -RoleDefinitionName "Storage Account Backup Contributor" `
                         -ResourceGroupName $config.sre.storage.rg
    if ($?) {
        Add-LogMessage -Level Success "Successfully created role assignment(s)"
    } else {
        Add-LogMessage -Level Fatal "Failed to create role assignment(s)"
    }
} else {
    Add-LogMessage -Level InfoSuccess "Role assignment(s) already exists"
}
