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
