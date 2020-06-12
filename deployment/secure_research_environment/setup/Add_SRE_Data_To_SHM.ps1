param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Create secrets resource group if it does not exist
# --------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.keyVault.rg -Location $config.sre.location


# Ensure the keyvault exists
# --------------------------
$_ = Deploy-KeyVault -Name $config.sre.keyVault.Name -ResourceGroupName $config.sre.keyVault.rg -Location $config.sre.location
Set-KeyVaultPermissions -Name $config.sre.keyVault.Name -GroupName $config.shm.adminSecurityGroupName
Set-AzKeyVaultAccessPolicy -VaultName $config.sre.keyVault.Name -ResourceGroupName $config.sre.keyVault.rg -EnabledForDeployment


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
# Load SRE groups
$groups = $config.sre.domain.securityGroups | ConvertTo-Json | ConvertFrom-Json -AsHashtable
# Load SRE LDAP users
$ldapUsers = $config.sre.users.ldap | ConvertTo-Json | ConvertFrom-Json -AsHashtable
foreach ($user in $ldapUsers.Keys) {
    $ldapUsers[$user]["password"] = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $ldapUsers[$user]["passwordSecretName"]
}
# Load other SRE service users
$serviceUsers = $config.sre.users.serviceAccounts | ConvertTo-Json | ConvertFrom-Json -AsHashtable
foreach ($user in $serviceUsers.Keys) {
    $serviceUsers[$user]["password"] = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $serviceUsers[$user]["passwordSecretName"]
}


# Add SRE users and groups to SHM
# -------------------------------
Add-LogMessage -Level Info "[ ] Adding SRE users and groups to SHM..."
$_ = Set-AzContext -Subscription $config.shm.subscriptionName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Create_New_SRE_User_Service_Accounts_Remote.ps1"
$params = @{
    shmLdapUserSgName = "`"$($config.shm.domain.securityGroups.dsvmLdapUsers.name)`""
    shmSystemAdministratorSgName = "`"$($config.shm.domain.securityGroups.serverAdmins.name)`""
    groupsB64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($groups | ConvertTo-Json)))
    ldapUsersB64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($ldapUsers | ConvertTo-Json)))
    researchUsersB64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($researchUsers | ConvertTo-Json)))
    serviceUsersB64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($serviceUsers | ConvertTo-Json)))
    researchUserOuPath = "`"$($config.shm.domain.userOuPath)`""
    securityOuPath = "`"$($config.shm.domain.securityOuPath)`""
    serviceOuPath = "`"$($config.shm.domain.serviceOuPath)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
