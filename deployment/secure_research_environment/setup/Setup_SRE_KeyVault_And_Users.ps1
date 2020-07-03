param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Networking.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Create secrets resource group if it does not exist
# --------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.keyVault.rg -Location $config.sre.location


# Ensure the keyvault exists
# --------------------------
$null = Deploy-KeyVault -Name $config.sre.keyVault.name -ResourceGroupName $config.sre.keyVault.rg -Location $config.sre.location
Set-KeyVaultPermissions -Name $config.sre.keyVault.name -GroupName $config.shm.adminSecurityGroupName
Set-AzKeyVaultAccessPolicy -VaultName $config.sre.keyVault.name -ResourceGroupName $config.sre.keyVault.rg -EnabledForDeployment


# Ensure that secrets exist in the keyvault
# -----------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.sre.keyVault.name)'..."
# :: Admin usernames
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
    Add-LogMessage -Level Success "Ensured that SRE admin usernames exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SRE admin usernames exist!"
}
# :: VM admin passwords
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.dsvm.adminPasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.dataserver.adminPasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.rds.gateway.adminPasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.rds.sessionHost1.adminPasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.rds.sessionHost2.adminPasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.adminPasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.hackmd.adminPasswordSecretName -DefaultLength 20
    Add-LogMessage -Level Success "Ensured that SRE VM admin passwords exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SRE VM admin passwords exist!"
}
# :: Databases
try {
    foreach ($dbConfigName in $config.sre.databases.Keys) {
        if ($config.sre.databases[$dbConfigName] -isnot [Hashtable]) { continue }
        $dbAdminUsername = "sre$($config.sre.id)dbadmin".ToLower()
        if ($dbConfigName -eq "dbpostgresql") { $dbAdminUsername = "postgres" } # This is recorded for auditing purposes - changing it will not change the username of the admin account
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.databases[$dbConfigName].adminPasswordSecretName -DefaultLength 20
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.databases[$dbConfigName].dbAdminUsernameSecretName $dbAdminUsername
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.databases[$dbConfigName].dbAdminPasswordSecretName -DefaultLength 20
    }
    Add-LogMessage -Level Success "Ensured that SRE database secrets exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that SRE database secrets exist!"
}
# :: Other secrets
try {
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.rootPasswordSecretName -DefaultLength 20
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.npsSecret -DefaultLength 12
    Add-LogMessage -Level Success "Ensured that other SRE secrets exist"
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that other SRE secrets exist!"
}


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Loading secrets for SRE users and groups..."
# Load SRE groups
$groups = $config.sre.domain.securityGroups
# Load SRE service users
$serviceUsers = $config.sre.users.serviceAccounts
foreach ($user in $serviceUsers.Keys) {
    $serviceUsers[$user]["password"] = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $serviceUsers[$user]["passwordSecretName"] -DefaultLength 20
}


# Add SRE users and groups to SHM
# -------------------------------
Add-LogMessage -Level Info "[ ] Adding SRE users and groups to SHM..."
$null = Set-AzContext -Subscription $config.shm.subscriptionName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Create_New_SRE_User_Service_Accounts_Remote.ps1"
$params = @{
    shmSystemAdministratorSgName = "`"$($config.shm.domain.securityGroups.serverAdmins.name)`""
    groupsB64                    = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($groups | ConvertTo-Json)))
    serviceUsersB64              = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($serviceUsers | ConvertTo-Json)))
    securityOuPath               = "`"$($config.shm.domain.ous.securityGroups.path)`""
    serviceOuPath                = "`"$($config.shm.domain.ous.serviceAccounts.path)`""
}
# shmLdapUserSgName = "`"$($config.shm.domain.securityGroups.computerManagers.name)`""
# computerManagersB64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($computerManagers | ConvertTo-Json)))
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext;
