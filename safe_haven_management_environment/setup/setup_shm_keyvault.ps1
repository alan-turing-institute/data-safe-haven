param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig ($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Create secrets resource group if it does not exist
# -----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.keyVault.rg -Location $config.location


# Ensure the keyvault exists
# --------------------------
Add-LogMessage -Level Info "Ensuring that key vault '$($config.keyVault.name)' exists..."
$keyVault = Get-AzKeyVault -VaultName $config.keyVault.Name -ResourceGroupName $config.keyVault.rg
if ($null -ne $keyVault) {
    Add-LogMessage -Level Success "Key vault $($config.keyVault.name) already exists"
} else {
    $_ = New-AzKeyVault -Name $config.keyVault.Name -ResourceGroupName $config.keyVault.rg -Location $config.location
    if ($?) {
        Add-LogMessage -Level Success "Created resource group $($config.keyVault.rg)"
    } else {
        Add-LogMessage -Level Fatal "Failed to create resource group $($config.keyVault.rg)!"
    }
}


# Set correct access policies for key vault
# -----------------------------------------
Add-LogMessage -Level Info "Setting correct access policies for key vault '$($config.keyVault.name)'..."
Set-AzKeyVaultAccessPolicy -VaultName $config.keyVault.Name -ObjectId (Get-AzADGroup -SearchString $config.adminSecurityGroupName)[0].Id `
                           -PermissionsToKeys Get,List,Update,Create,Import,Delete,Backup,Restore,Recover `
                           -PermissionsToSecrets Get,List,Set,Delete,Recover,Backup,Restore `
                           -PermissionsToCertificates Get,List,Delete,Create,Import,Update,Managecontacts,Getissuers,Listissuers,Setissuers,Deleteissuers,Manageissuers,Recover,Backup,Restore
$success = $?
Remove-AzKeyVaultAccessPolicy -VaultName $config.keyVault.Name -UserPrincipalName (Get-AzContext).Account.Id
$success = $success -and $?
if ($success) {
    Add-LogMessage -Level Success "Set correct access policies"
} else {
    Add-LogMessage -Level Fatal "Failed to set correct access policies!"
}

# Ensure that secrets exist in the keyvault
# -----------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.keyVault.name)'..."
# :: AAD Global Administrator password
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.aadAdminPassword
if ($?) {
    Add-LogMessage -Level Success "AAD Global Administrator password exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create AAD Global Administrator password!"
}

# :: DC/NPS administrator username
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcNpsAdminUsername -defaultValue "shm$($config.id)admin".ToLower()
if ($?) {
    Add-LogMessage -Level Success "DC/NPS administrator username exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create DC/NPS administrator username!"
}

# :: DC/NPS administrator password
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcNpsAdminPassword
if ($?) {
    Add-LogMessage -Level Success "DC/NPS administrator password exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create DC/NPS administrator password!"
}

# :: DC safe mode password
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcSafemodePassword
if ($?) {
    Add-LogMessage -Level Success "DC safe mode password exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create DC safe mode password!"
}

# :: AD sync password
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.adsyncPassword
if ($?) {
    Add-LogMessage -Level Success "AD sync password exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create AD sync password!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
