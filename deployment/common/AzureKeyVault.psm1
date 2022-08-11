Import-Module Az.KeyVault -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Create a key vault if it does not exist
# ---------------------------------------
function Deploy-KeyVault {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of disk to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location
    )
    Add-LogMessage -Level Info "Ensuring that key vault '$Name' exists..."
    $keyVault = Get-AzKeyVault -VaultName $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if ($null -eq $keyVault) {
        # Purge any existing soft-deleted key vault
        foreach ($existingLocation in (Get-AzLocation | ForEach-Object { $_.Location })) {
            try {
                if (Get-AzKeyVault -VaultName $Name -Location $existingLocation -InRemovedState -ErrorAction Stop -WarningAction SilentlyContinue) {
                    Add-LogMessage -Level Info "Purging a soft-deleted key vault '$Name' in $existingLocation"
                    Remove-AzKeyVault -VaultName $Name -Location $existingLocation -InRemovedState -Force -WarningAction SilentlyContinue | Out-Null
                    if ($?) {
                        Add-LogMessage -Level Success "Purged key vault '$Name'"
                    } else {
                        Add-LogMessage -Level Fatal "Failed to purge key vault '$Name'!"
                    }
                }
            } catch [Microsoft.Rest.Azure.CloudException] {
                continue  # Running Get-AzKeyVault on a location which does not support soft-deleted key vaults causes an error which we catch here
            }
        }
        # Create a new key vault
        Add-LogMessage -Level Info "[ ] Creating key vault '$Name'"
        $keyVault = New-AzKeyVault -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -WarningAction SilentlyContinue
        if ($?) {
            Add-LogMessage -Level Success "Created key vault '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create key vault '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Key vault '$Name' already exists"
    }
    return $keyVault
}
Export-ModuleMember -Function Deploy-KeyVault


# Set key vault permissions to the group and remove the user who deployed it
# --------------------------------------------------------------------------
function Set-KeyVaultPermissions {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault to set the permissions on")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of group to give permissions to")]
        [string]$GroupName
    )
    Add-LogMessage -Level Info "Giving group '$GroupName' access to key vault '$Name'..."
    try {
        $securityGroupId = (Get-AzADGroup -DisplayName $GroupName).Id | Select-Object -First 1
    } catch [Microsoft.Azure.Commands.ActiveDirectory.GetAzureADGroupCommand] {
        Add-LogMessage -Level Fatal "Could not identify an Azure security group called $GroupName!"
    }
    Set-AzKeyVaultAccessPolicy -VaultName $Name `
                               -ObjectId $securityGroupId `
                               -PermissionsToKeys Get, List, Update, Create, Import, Delete, Backup, Restore, Recover, Purge `
                               -PermissionsToSecrets Get, List, Set, Delete, Recover, Backup, Restore, Purge `
                               -PermissionsToCertificates Get, List, Delete, Create, Import, Update, Managecontacts, Getissuers, Listissuers, Setissuers, Deleteissuers, Manageissuers, Recover, Backup, Restore, Purge `
                               -WarningAction SilentlyContinue
    $success = $?
    foreach ($accessPolicy in (Get-AzKeyVault $Name -WarningAction SilentlyContinue).AccessPolicies | Where-Object { $_.ObjectId -ne $securityGroupId }) {
        Remove-AzKeyVaultAccessPolicy -VaultName $Name -ObjectId $accessPolicy.ObjectId -WarningAction SilentlyContinue
        $success = $success -and $?
    }
    if ($success) {
        Add-LogMessage -Level Success "Set correct access policies for key vault '$Name'"
    } else {
        Add-LogMessage -Level Fatal "Failed to set correct access policies for key vault '$Name'!"
    }
}
Export-ModuleMember -Function Set-KeyVaultPermissions
