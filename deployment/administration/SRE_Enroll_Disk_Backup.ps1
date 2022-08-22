param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter the name of the resource group containing the new disk")]
    [string]$resourceGroup,
    [Parameter(Mandatory = $true, HelpMessage = "Enter the name of the new disk")]
    [string]$diskName
)

Import-Module $PSScriptRoot/../common/AzureDataProtection -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop

$config = Get-SreConfig -shmId $shmId -sreId $sreId
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop

# Get backup vault
$Vault = Get-AzDataProtectionBackupVault -ResourceGroupName $config.sre.backup.rg `
                                         -VaultName $config.sre.backup.vault.name `

# Get disk backup policy
$Policy = Get-AzDataProtectionBackupPolicy -Name $config.sre.backup.disk.policy_name `
                                           -ResourceGroupName $config.sre.backup.rg `
                                           -VaultName $Vault.Name

# Create backup instance for named disk
$Disk = Get-AzDisk -ResourceGroupName $resourceGroup -DiskName $diskName
$null = Deploy-DataProtectionBackupInstance -BackupPolicyId $Policy.Id `
                                            -ResourceGroupName $config.sre.backup.rg `
                                            -VaultName $Vault.Name `
                                            -DataSourceType 'disk' `
                                            -DataSourceId $Disk.Id `
                                            -DataSourceLocation $Disk.Location `
                                            -DataSourceName $Disk.Name
