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
$hackmdPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.hackmdLdapPassword
$gitlabPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.gitlabLdapPassword
$dsvmPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmLdapPassword
$testResearcherPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.testResearcherPassword
# Encrypt passwords for passing to script
$hackmdPasswordEncrypted = ConvertTo-SecureString $hackmdPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$gitlabPasswordEncrypted = ConvertTo-SecureString $gitlabPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$dsvmPasswordEncrypted = ConvertTo-SecureString $dsvmPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$testResearcherPasswordEncrypted = ConvertTo-SecureString $testResearcherPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)


# Add SRE users and groups to SHM
# -------------------------------
Add-LogMessage -Level Info "[ ] Adding SRE users and groups to SHM..."
$_ = Set-AzContext -Subscription $config.shm.subscriptionName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Create_New_SRE_User_Service_Accounts_Remote.ps1"
$params = @{
    shmFqdn = "`"$($config.shm.domain.fqdn)`""
    sreFqdn = "`"$($config.sre.domain.fqdn)`""
    researchUserSgName = "`"$($config.sre.domain.securityGroups.researchUsers.name)`""
    researchUserSgDescription = "`"$($config.sre.domain.securityGroups.researchUsers.description)`""
    ldapUserSgName = "`"$($config.shm.domain.securityGroups.dsvmLdapUsers.name)`""
    securityOuPath = "`"$($config.shm.domain.securityOuPath)`""
    serviceOuPath = "`"$($config.shm.domain.serviceOuPath)`""
    researchUserOuPath = "`"$($config.shm.domain.userOuPath)`""
    hackmdSamAccountName = "`"$($config.sre.users.ldap.hackmd.samAccountName)`""
    hackmdName = "`"$($config.sre.users.ldap.hackmd.name)`""
    hackmdPasswordEncrypted = $hackmdPasswordEncrypted
    gitlabSamAccountName = "`"$($config.sre.users.ldap.gitlab.samAccountName)`""
    gitlabName = "`"$($config.sre.users.ldap.gitlab.name)`""
    gitlabPasswordEncrypted = $gitlabPasswordEncrypted
    dsvmSamAccountName = "`"$($config.sre.users.ldap.dsvm.samAccountName)`""
    dsvmName = "`"$($config.sre.users.ldap.dsvm.name)`""
    dsvmPasswordEncrypted = $dsvmPasswordEncrypted
    testResearcherSamAccountName = "`"$($config.sre.users.researchers.test.samAccountName)`""
    testResearcherName = "`"$($config.sre.users.researchers.test.name)`""
    testResearcherPasswordEncrypted = $testResearcherPasswordEncrypted
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Add SRE DNS entries to SHM
# --------------------------
Add-LogMessage -Level Info "[ ] Adding SRE DNS records to SHM..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Add_New_SRE_To_DNS_Remote.ps1"
$params = @{
    shmFqdn = "`"$($config.shm.domain.fqdn)`""
    sreFqdn = "`"$($config.sre.domain.fqdn)`""
    sreDcIp = "`"$($config.sre.dc.ip)`""
    sreDcName = "`"$($config.sre.dc.hostname)`""
    identitySubnetCidr = "`"$($config.sre.network.subnets.identity.cidr)`""
    rdsSubnetCidr = "`"$($config.sre.network.subnets.rds.cidr)`""
    dataSubnetCidr = "`"$($config.sre.network.subnets.data.cidr)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
