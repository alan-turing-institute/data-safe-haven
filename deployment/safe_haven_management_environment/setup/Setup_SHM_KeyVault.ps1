param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Create secrets resource group if it does not exist
# --------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.keyVault.rg -Location $config.location


# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------
$_ = Deploy-KeyVault -Name $config.keyVault.name -ResourceGroupName $config.keyVault.rg -Location $config.location
Set-KeyVaultPermissions -Name $config.keyVault.name -GroupName $config.adminSecurityGroupName


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
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcNpsAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()
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
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.localAdsyncPassword
if ($?) {
    Add-LogMessage -Level Success "AD sync password exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create AD sync password!"
}

# :: AD test user password
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.testAdUserPassword
if ($?) {
    Add-LogMessage -Level Success "Test user password exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create test user password!"
}

# :: Package mirror administrator username
$_ = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.mirrorAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()
if ($?) {
    Add-LogMessage -Level Success "Package mirror administrator username exists"
} else {
    Add-LogMessage -Level Fatal "Failed to create package mirror administrator username!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
