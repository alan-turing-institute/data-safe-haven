Import-Module Az.KeyVault -ErrorAction Stop
Import-Module $PSScriptRoot/Cryptography -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
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


# Purge a secret from the keyvault
# --------------------------------
function Remove-AndPurgeKeyVaultSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of secret")]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault this secret belongs to")]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName
    )
    Remove-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -Force -ErrorAction Stop
    # Wait up to five minutes for the secret to show up as purgeable
    for ($i = 0; $i -lt 30; $i++) {
        if (Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -InRemovedState) {
            Remove-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -InRemovedState -Force -ErrorAction Stop
            break
        }
        Start-Sleep -Seconds 10
    }
}
Export-ModuleMember -Function Remove-AndPurgeKeyVaultSecret


# Return a certificate with a valid private key if it exists, otherwise remove and purge any certificate with this name
# ---------------------------------------------------------------------------------------------------------------------
function Resolve-KeyVaultPrivateKeyCertificate {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of secret")]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault this secret belongs to")]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName
    )
    # Return existing certificate if it exists and has a private key
    $existingCert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName
    $privateKey = Get-AzKeyVaultSecret -VaultName $VaultName -Name $CertificateName -AsPlainText
    if ($existingCert -and $privateKey) {
        Add-LogMessage -Level InfoSuccess "Found existing certificate with private key"
        return $existingCert
    }
    # Remove any existing certificate with this name
    Remove-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -Force -ErrorAction SilentlyContinue
    Wait-For -Target "removal of old certificate to complete" -Seconds 30
    # Purge any removed certificate with this name
    $removedCert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -InRemovedState
    if ($removedCert) {
        Remove-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -InRemovedState -Force -ErrorAction SilentlyContinue
        Wait-For -Target "pruning of old certificate to complete" -Seconds 30
    }
    return $false
}
Export-ModuleMember -Function Resolve-KeyVaultPrivateKeyCertificate


# Ensure that a password is in the keyvault
# -----------------------------------------
function Resolve-KeyVaultSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of secret")]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault this secret belongs to")]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,
        [Parameter(Mandatory = $false, HelpMessage = "Default value for this secret")]
        [string]$DefaultValue,
        [Parameter(Mandatory = $false, HelpMessage = "Default number of random characters to be used when initialising this secret")]
        [string]$DefaultLength,
        [Parameter(Mandatory = $false, HelpMessage = "Overwrite any existing secret with this name")]
        [switch]$ForceOverwrite,
        [Parameter(Mandatory = $false, HelpMessage = "Retrieve secret as plaintext instead of as a secure string")]
        [switch]$AsPlaintext
    )
    # Create a new secret if one does not exist in the key vault or if we are forcing an overwrite
    if ($ForceOverwrite -or (-not (Get-AzKeyVaultSecret -Name $SecretName -VaultName $VaultName))) {
        # If no default is provided then we cannot generate a secret
        if ((-not $DefaultValue) -and (-not $DefaultLength)) {
            Add-LogMessage -Level Fatal "Secret '$SecretName does not exist and no default value or length was provided!"
        }
        # If both defaults are provided then we do not know which to use
        if ($DefaultValue -and $DefaultLength) {
            Add-LogMessage -Level Fatal "Both a default value and a default length were provided. Please only use one of these options!"
        }
        # Generate a new password if there is no default value
        if (-not $DefaultValue) {
            $DefaultValue = $(New-Password -Length $DefaultLength)
        }
        # Store the password in the keyvault
        try {
            $null = Undo-AzKeyVaultSecretRemoval -Name $SecretName -VaultName $VaultName -ErrorAction SilentlyContinue # if the key has been soft-deleted we need to restore it before doing anything else
            Start-Sleep 10
            $null = Set-AzKeyVaultSecret -Name $SecretName -VaultName $VaultName -SecretValue (ConvertTo-SecureString $DefaultValue -AsPlainText -Force) -ErrorAction Stop
        } catch [Microsoft.Azure.KeyVault.Models.KeyVaultErrorException] {
            Add-LogMessage -Level Fatal "Failed to create '$SecretName' in key vault '$VaultName'" -Exception $_.Exception
        }
    }
    # Retrieve the secret from the key vault and return its value
    $secret = Get-AzKeyVaultSecret -Name $SecretName -VaultName $VaultName
    if ($AsPlaintext) { return $secret.SecretValue | ConvertFrom-SecureString -AsPlainText }
    return $secret.SecretValue
}
Export-ModuleMember -Function Resolve-KeyVaultSecret


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
