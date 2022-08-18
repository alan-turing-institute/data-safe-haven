Import-Module Az.DataProtection -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop

$DataSourceMap = @{
    "blob" = "AzureBlob"
    "disk" = "AzureDisk"
}

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


# Deploy a data protection backup instance
# ----------------------------------------
function Deploy-DataProtectionBackupInstance {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "ID of the backup policy to apply")]
        [string]$BackupPolicyId,
        [Parameter(Mandatory = $true, HelpMessage = "Name of data protection backup vault resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of data protection backup vault")]
        [string]$VaultName,
        [Parameter(Mandatory = $true, HelpMessage = "backup data source type")]
        [ValidateScript({$_ -in $DataSourceMap.Keys})]
        [string]$DataSourceType,
        [Parameter(Mandatory = $true, HelpMessage = "ID of the resource to enable backup on")]
        [String]$DataSourceId,
        [Parameter(Mandatory = $true, HelpMessage = "Location of the resource to enable backup on")]
        [String]$DataSourceLocation,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the resource to enable backup on")]
        [String]$DataSourceName
    )
    Add-LogMessage -Level Info "Ensuring backup instance for '$DataSourceName' exists"
    $instance = Get-AzDataProtectionBackupInstance -ResourceGroupName $ResourceGroupName -VaultName $VaultName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$DataSourceName*" }
    if ($instance) {
        Add-LogMessage -Level InfoSuccess "Backup instance for '$DataSourceName' already exists"
    } else {
        try {
            Add-LogMessage -Level Info "[ ] Creating backup instance for '$DataSourceName'"
            $initialisation = Initialize-AzDataProtectionBackupInstance -DatasourceType $DataSourceMap[$DataSourceType] `
                                                                        -DatasourceLocation $DataSourceLocation `
                                                                        -PolicyId $BackupPolicyId `
                                                                        -DatasourceId $DataSourceId `
                                                                        -ErrorAction Stop
            if ($DataSourceType -eq 'disk'){
                # Set resource group to hold snapshots
                $backup_rg_id = (Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -eq $ResourceGroupName}).ResourceId
                $initialisation.Property.PolicyInfo.PolicyParameter.DataStoreParametersList[0].ResourceGroupId = $backup_rg_id
            }
            $instance = New-AzDataProtectionBackupInstance -ResourceGroupName $ResourceGroupName `
                                                           -VaultName $VaultName `
                                                           -BackupInstance $initialisation `
                                                           -ErrorAction Stop
            Add-LogMessage -Level Success "Successfully deployed backup instance for '$DataSourceName'"
        } catch {
            Add-LogMessage -Level Fatal "Failed to deploy backup instance for '$DataSourceName'" -Exception $_.Exception
        }
    }
    return $instance
}
Export-ModuleMember -Function Deploy-DataProtectionBackupInstance

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
        [Parameter(Mandatory = $true, HelpMessage = "backup data source type")]
        [ValidateScript({$_ -in $DataSourceMap.Keys})]
        [string]$DataSourceType
    )

    Add-LogMessage -Level Info "Ensuring backup policy '$PolicyName' exists"
    try {
        $Policy = Get-AzDataProtectionBackupPolicy -Name $PolicyName `
                                                   -ResourceGroupName $ResourceGroupName `
                                                   -VaultName $VaultName `
                                                   -ErrorAction Stop
        Add-LogMessage -Level InfoSuccess "Backup policy '$PolicyName' already exists"
    } catch {
        Add-LogMessage -Level Info "[ ] Creating backup policy '$PolicyName'"
        $Template = Get-AzDataProtectionPolicyTemplate -DatasourceType $DataSourceMap[$DataSourceType]
        $Policy = New-AzDataProtectionBackupPolicy -ResourceGroupName $ResourceGroupName `
                                                   -VaultName $VaultName `
                                                   -Name $PolicyName `
                                                   -Policy $Template
        if ($?) {
            Add-LogMessage -Level Success "Successfully deployed backup policy $PolicyName"
        } else {
            Add-LogMessage -Level Fatal "Failed to deploy backup policy $PolicyName"
        }
    }
    return $Policy
}
Export-ModuleMember -Function Deploy-DataProtectionBackupPolicy


# Remove all data protection backup instances
# -------------------------------------------
function Remove-DataProtectionBackupInstances {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of data protection backup vault resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of data protection backup vault")]
        [string]$VaultName
    )
    try {
        $Instances = Get-AzDataProtectionBackupInstance -ResourceGroupName $ResourceGroupName -VaultName $VaultName -ErrorAction SilentlyContinue
        if ($Instances) {
            Add-LogMessage -Level Info "Attempting to remove backup instances from vault '$VaultName' in resource group '$ResourceGroupName'..."
            $null = $Instances | Remove-AzDataProtectionBackupInstance -ErrorAction Stop
            Add-LogMessage -Level Success "Removed backup instances from vault '$VaultName' in resource group '$ResourceGroupName'"
        }
    } catch {
        Add-LogMessage -Level Fatal "Failed to remove backup instances from vault '$VaultName' in resource group '$ResourceGroupName'!"
    }
}
Export-ModuleMember -Function Remove-DataProectionBackupInstances
