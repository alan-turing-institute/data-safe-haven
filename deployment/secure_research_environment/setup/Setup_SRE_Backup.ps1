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
$null = Deploy-DataProtectionBackupVault -ResourceGroupName $config.sre.backup.rg `
                                         -VaultName $config.sre.backup.vault.name `
                                         -Location $config.sre.location

# Create blob backup policy
# This enforces the default policy for blobs
$policy_name = $config.sre.backup.blob.policy_name
Add-LogMessage -Level Info "Ensuring backup policy '$policy_name' is configured"
$blob_policy = Get-AzDataProtectionBackupPolicy -Name $policy_name `
                                                -ResourceGroupName $config.sre.backup.rg `
                                                -VaultName $config.sre.backup.vault.name `
                                                -ErrorVariable $notExists `
                                                -ErrorAction SilentlyContinue
if($notExists) {
    Add-LogMessage -Level Info "[ ] Creating backup policy '$policy_name'"
    $blob_policy = Get-AzDataProtectionPolicyTemplate -DatasourceType AzureBlob
    $null = New-AzDataProtectionBackupPolicy -ResourceGroupName $config.sre.backup.rg `
                                             -VaultName $config.sre.backup.vault.name `
                                             -Name $policy_name `
                                             -Policy $blob_policy
    if ($?) {
            Add-LogMessage -Level Success "Successfully deployed backup policy $policy_name"
        } else {
            Add-LogMessage -Level Fatal "Failed to deploy backup policy $policy_name"
        }
} else {
    Add-LogMessage -Level InfoSuccess "Backup policy '$policy_name' already exists"
}
