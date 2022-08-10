Import-Module Az.DataProtection -ErrorAction Stop


# Deploy a data protection backup vault
# -------------------------------------
function Deploy-DataProtectionBackupVault {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of backup resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of data protection backup vault")]
        [string]$VaultName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of data protection backup vault")]
        [string]$Location
    )
    # Check if vault exists
    Add-LogMessage -Level Info "Ensuring that backup vault '$VaultName' exists..."
    try {
        $Vault = Get-AzDataProtectionBackupVault -ResourceGroupName $ResourceGroupName `
                                                 -VaultName $VaultName `
                                                 -ErrorAction Stop
        Add-LogMessage -Level InfoSuccess "Backup vault '$VaultName' already exists"
    } catch {
        Add-LogMessage -Level Info "[ ] Creating backup vault '$VaultName'"
        $storagesetting = New-AzDataProtectionBackupVaultStorageSettingObject -DataStoreType VaultStore -Type LocallyRedundant
        # Create backup vault
        # The SystemAssigned identity is necessary to give the backup vault
        # appropriate permissions to backup resources.
        $Vault = New-AzDataProtectionBackupVault -ResourceGroupName $ResourceGroupName `
                                                 -VaultName $VaultName `
                                                 -StorageSetting $storagesetting `
                                                 -Location $Location `
                                                 -IdentityType "SystemAssigned"
        if ($?) {
            Add-LogMessage -Level Success "Successfully deployed backup vault $VaultName"
        } else {
            Add-LogMessage -Level Fatal "Failed to deploy backup vault $VaultName"
        }
    }
    return $Vault
}
Export-ModuleMember -Function Deploy-DataProtectionBackupVault


# Deploy a data protection backup policy
# Currently only supports default policies
# ----------------------------------------
function Deploy-DataProtectionBackupPolicy {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of backup resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of data protection backup vault")]
        [string]$VaultName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of data protection backup policy")]
        [string]$PolicyName,
        [Parameter(Mandatory = $true, HelpMessage = "backup data source")]
        [ValidateSet("blob")]
        [string]$DataSourceType
    )
    $DataSourceMap = @{
        "blob" = "AzureBlob"
    }
    Add-LogMessage -Level Info "Ensuring backup policy '$PolicyName' exists"
    try {
        $Policy = Get-AzDataProtectionBackupPolicy -Name $PolicyName `
                                                   -ResourceGroupName $ResourceGroupName `
                                                   -VaultName $VaultName `
                                                   -ErrorAction Stop
        Add-LogMessage -Level InfoSuccess "Backup policy '$PolicyName' already exists"
    } catch {
        Add-LogMessage -Level Info "[ ] Creating backup policy '$PolicyName'"
        $Policy = Get-AzDataProtectionPolicyTemplate -DatasourceType $DataSourceMap[$DataSourceType]
        $null = New-AzDataProtectionBackupPolicy -ResourceGroupName $ResourceGroupName `
                                                 -VaultName $VaultName `
                                                 -Name $PolicyName `
                                                 -Policy $Policy
        if ($?) {
            Add-LogMessage -Level Success "Successfully deployed backup policy $PolicyName"
        } else {
            Add-LogMessage -Level Fatal "Failed to deploy backup policy $PolicyName"
        }
    }
    return $Policy
}
Export-ModuleMember -Function Deploy-DataProtectionBackupPolicy