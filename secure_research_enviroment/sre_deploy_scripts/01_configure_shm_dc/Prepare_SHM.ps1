param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# Get SRE config
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext

# Directory for local and remote helper scripts
$helperScriptDir = Join-Path $PSScriptRoot "helper_scripts" "Prepare_SHM" -Resolve

# Switch to SRE subscription
# --------------------------
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;


# Ensure the resource group exists
# --------------------------------
Write-Host -ForegroundColor DarkCyan "Ensuring resource group '$($config.dsg.keyVault.rg)' exists..."
$_ = New-AzResourceGroup -Name $config.dsg.keyVault.rg  -Location $config.dsg.location -Force
if ($?) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}


# Ensure the keyvault exists
# --------------------------
Write-Host -ForegroundColor DarkCyan "Ensuring key vault exists..."
$keyVault = Get-AzKeyVault -VaultName $config.dsg.keyVault.name -ResourceGroupName $config.dsg.keyVault.rg
if ($keyVault -ne $null) {
  Write-Host -ForegroundColor DarkGreen " [o] key vault $($config.dsg.keyVault.name) already exists"
} else {
  New-AzKeyVault -Name $config.dsg.keyVault.name  -ResourceGroupName $config.dsg.keyVault.rg -Location $config.dsg.location -EnabledForDeployment
  if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] Created key vault $($config.dsg.keyVault.name)"
  } else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to create key vault $($config.dsg.keyVault.name)!"
  }
}

# Switch to SHM subscription
# --------------------------
$_ = Set-AzContext -Subscription $config.shm.subscriptionName;

# Retrieve passwords from the keyvault
Write-Host -ForegroundColor DarkCyan "Creating/retrieving user passwords..."
$hackmdPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.hackmdLdapPassword
$gitlabPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.gitlabLdapPassword
$dsvmPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmLdapPassword
$testResearcherPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.testResearcherPassword

# Encrypt passwords for passing to script
$hackmdPasswordEncrypted = ConvertTo-SecureString $hackmdPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$gitlabPasswordEncrypted = ConvertTo-SecureString $gitlabPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$dsvmPasswordEncrypted = ConvertTo-SecureString $dsvmPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$testResearcherPasswordEncrypted = ConvertTo-SecureString $testResearcherPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)


# === Add DSG users and groups to SHM ====
Write-Host -ForegroundColor DarkCyan "Adding SRE users and groups to SHM..."
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Create_New_SRE_User_Service_Accounts_Remote.ps1"
$params = @{
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    researchUserSgName = "`"$($config.dsg.domain.securityGroups.researchUsers.name)`""
    researchUserSgDescription = "`"$($config.dsg.domain.securityGroups.researchUsers.description)`""
    ldapUserSgName = "`"$($config.shm.domain.securityGroups.dsvmLdapUsers.name)`""
    securityOuPath = "`"$($config.shm.domain.securityOuPath)`""
    serviceOuPath = "`"$($config.shm.domain.serviceOuPath)`""
    researchUserOuPath = "`"$($config.shm.domain.userOuPath)`""
    hackmdSamAccountName = "`"$($config.dsg.users.ldap.hackmd.samAccountName)`""
    hackmdName = "`"$($config.dsg.users.ldap.hackmd.name)`""
    hackmdPasswordEncrypted = $hackmdPasswordEncrypted
    gitlabSamAccountName = "`"$($config.dsg.users.ldap.gitlab.samAccountName)`""
    gitlabName = "`"$($config.dsg.users.ldap.gitlab.name)`""
    gitlabPasswordEncrypted = $gitlabPasswordEncrypted
    dsvmSamAccountName = "`"$($config.dsg.users.ldap.dsvm.samAccountName)`""
    dsvmName = "`"$($config.dsg.users.ldap.dsvm.name)`""
    dsvmPasswordEncrypted = $dsvmPasswordEncrypted
    testResearcherSamAccountName = "`"$($config.dsg.users.researchers.test.samAccountName)`""
    testResearcherName = "`"$($config.dsg.users.researchers.test.name)`""
    testResearcherPasswordEncrypted = $testResearcherPasswordEncrypted
}
$result = Invoke-AzVMRunCommand -Name $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
if ($?) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}
Write-Output $result.Value


# Add DSG DNS entries to SHM
# --------------------------
Write-Host -ForegroundColor DarkCyan "Adding SRE DNS records to SHM..."
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Add_New_SRE_To_DNS_Remote.ps1"
$params = @{
    shmFqdn = "`"$($config.shm.domain.fqdn)`""
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    dsgDcIp = "`"$($config.dsg.dc.ip)`""
    dsgDcName = "`"$($config.dsg.dc.hostname)`""
    identitySubnetCidr = "`"$($config.dsg.network.subnets.identity.cidr)`""
    rdsSubnetCidr = "`"$($config.dsg.network.subnets.rds.cidr)`""
    dataSubnetCidr = "`"$($config.dsg.network.subnets.data.cidr)`""
}
$result = Invoke-AzVMRunCommand -Name $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
if ($?) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}
Write-Output $result.Value


# Update SRE keyvault permissions
# -------------------------------
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
Write-Host -ForegroundColor DarkCyan "Updating SRE keyvault permissions..."
try {
    Set-AzKeyVaultAccessPolicy -VaultName $config.dsg.keyVault.name -ObjectId (Get-AzADGroup -SearchString $config.shm.adminSecurityGroupName)[0].Id -PermissionsToKeys Get, List, Update, Create, Import, Delete, Backup, Restore, Recover -PermissionsToSecrets Get, List, Set, Delete, Recover, Backup, Restore -PermissionsToCertificates Get, List, Delete, Create, Import, Update, Managecontacts, Getissuers, Listissuers, Setissuers, Deleteissuers, Manageissuers, Recover, Backup, Restore
    Remove-AzKeyVaultAccessPolicy -VaultName $config.dsg.keyVault.name -UserPrincipalName (Get-AzContext).Account.Id
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} catch {
    Write-Host -ForegroundColor DarkRed " [x] Failed! Please check the permissions for '$($config.dsg.keyVault.name)' manually."
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;

