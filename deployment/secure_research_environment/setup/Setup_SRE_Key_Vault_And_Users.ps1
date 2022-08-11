param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Create secrets resource group if it does not exist
# --------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.keyVault.rg -Location $config.sre.location


# Ensure the Key Vault exists
# ---------------------------
$null = Deploy-KeyVault -Name $config.sre.keyVault.name -ResourceGroupName $config.sre.keyVault.rg -Location $config.sre.location
Set-KeyVaultPermissions -Name $config.sre.keyVault.name -GroupName $config.shm.azureAdminGroupName
Set-AzKeyVaultAccessPolicy -VaultName $config.sre.keyVault.name -ResourceGroupName $config.sre.keyVault.rg -EnabledForDeployment


# Ensure that secrets exist in the Key Vault
# -----------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in Key Vault '$($config.sre.keyVault.name)'..."
# :: Admin usernames
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext
    Add-LogMessage -Level Success "Ensured that SRE admin usernames exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SRE admin usernames exist!" -Exception $_.Exception
}
# :: VM admin passwords
try {
    # Remote desktop
    if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.remoteDesktop.guacamole.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    } elseif ($config.sre.remoteDesktop.provider -eq "MicrosoftRDS") {
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.remoteDesktop.gateway.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.remoteDesktop.appSessionHost.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    } else {
        Add-LogMessage -Level Fatal "Remote desktop type '$($config.sre.remoteDesktop.type)' was not recognised!"
    }
    # Other VMs
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.srd.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.cocalc.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.codimd.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
    Add-LogMessage -Level Success "Ensured that SRE VM admin passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SRE VM admin passwords exist!" -Exception $_.Exception
}
# :: Databases
try {
    foreach ($keyName in $config.sre.databases.Keys) {
        if ($config.sre.databases[$keyName] -isnot [System.Collections.IDictionary]) { continue }
        $dbAdminUsername = ($keyName -eq "dbpostgresql") ? "postgres" : "sre$($config.sre.id)dbadmin".ToLower() # The postgres admin username is hardcoded as 'postgres' but we save it to the keyvault to ensure a consistent record structure
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.databases[$keyName].adminPasswordSecretName -DefaultLength 20 -AsPlaintext
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.databases[$keyName].dbAdminUsernameSecretName $dbAdminUsername -AsPlaintext
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.databases[$keyName].dbAdminPasswordSecretName -DefaultLength 20 -AsPlaintext
    }
    Add-LogMessage -Level Success "Ensured that SRE database secrets exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SRE database secrets exist!" -Exception $_.Exception
}
# :: Other secrets
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.rootPasswordSecretName -DefaultLength 20 -AsPlaintext
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.npsSecret -DefaultLength 12 -AsPlaintext
    Add-LogMessage -Level Success "Ensured that other SRE secrets exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that other SRE secrets exist!" -Exception $_.Exception
}


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Loading secrets for SRE users and groups..."
# Load SRE groups
$groups = $config.sre.domain.securityGroups
# Load SRE service users
$serviceUsers = $config.sre.users.serviceAccounts
foreach ($user in $serviceUsers.Keys) {
    $serviceUsers[$user]["password"] = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $serviceUsers[$user]["passwordSecretName"] -DefaultLength 20 -AsPlaintext
}


# Add SRE users and groups to SHM
# -------------------------------
Add-LogMessage -Level Info "[ ] Adding SRE users and groups to SHM..."
$null = Set-AzContext -Subscription $config.shm.subscriptionName -ErrorAction Stop
$params = @{
    shmSystemAdministratorSgName = $config.shm.domain.securityGroups.serverAdmins.name
    groupsB64                    = $groups | ConvertTo-Json -Depth 99 | ConvertTo-Base64
    serviceUsersB64              = $serviceUsers | ConvertTo-Json -Depth 99 | ConvertTo-Base64
    securityOuPath               = $config.shm.domain.ous.securityGroups.path
    serviceOuPath                = $config.shm.domain.ous.serviceAccounts.path
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Create_New_SRE_User_Service_Accounts_Remote.ps1"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
