param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($sreId);


# Directory for local and remote helper scripts
$helperScriptDir = Join-Path $PSScriptRoot "helper_scripts" "Prepare_SHM" -Resolve

# Create DSG KeyVault if it does not exist
# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -Subscription $config.dsg.subscriptionName;

# Create Resource Groups
New-AzResourceGroup -Name $config.dsg.keyVault.rg  -Location $config.dsg.location -Force


# Ensure the keyvault exists
# --------------------------
$keyVault = Get-AzKeyVault -VaultName $config.dsg.keyVault.name -ResourceGroupName $config.dsg.keyVault.rg
if ($keyVault -ne $null) {
  Write-Host " [o] key vault $($config.dsg.keyVault.name) already exists"
} else {
  New-AzKeyVault -Name $config.dsg.keyVault.name  -ResourceGroupName $config.dsg.keyVault.rg -Location $config.dsg.location
  if ($?) {
    Write-Host " [o] Created key vault $($config.dsg.keyVault.name)"
  } else {
    Write-Host " [x] Failed to create key vault $($config.dsg.keyVault.name)!"
  }
}

# Temporarily switch to management subscription
$_ = Set-AzContext -Subscription $config.shm.subscriptionName;

# === Add DSG users and groups to SHM ====
Write-Host "Creating or retrieving user passwords"
$hackmdPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.users.ldap.hackmd.passwordSecretName
$gitlabPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.users.ldap.gitlab.passwordSecretName
$dsvmPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.users.ldap.dsvm.passwordSecretName
$testResearcherPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.users.researchers.test.passwordSecretName

# Encrypt passwords for passing to script
$hackmdPasswordEncrypted = ConvertTo-SecureString $hackmdPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$gitlabPasswordEncrypted = ConvertTo-SecureString $gitlabPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$dsvmPasswordEncrypted = ConvertTo-SecureString $dsvmPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$testResearcherPasswordEncrypted = ConvertTo-SecureString $testResearcherPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)


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
Write-Host "Adding SRE users and groups to SHM"
Write-Host ($params | Out-String)
$result = Invoke-AzVMRunCommand -Name $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
Write-Output $result.Value

# === Add DSG DNS entries to SHM ====
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Add_New_SRE_To_DNS_Remote.ps1"
$params = @{
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    dsgDcIp = "`"$($config.dsg.dc.ip)`""
    identitySubnetCidr = "`"$($config.dsg.network.subnets.identity.cidr)`""
    rdsSubnetCidr = "`"$($config.dsg.network.subnets.rds.cidr)`""
    dataSubnetCidr = "`"$($config.dsg.network.subnets.data.cidr)`""
}
Write-Host "Adding SRE DNS records to SHM"
$result = Invoke-AzVMRunCommand -Name $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
Write-Output $result.Value

Set-AzKeyVaultAccessPolicy -VaultName $config.dsg.keyVault.name -ObjectId (Get-AzADGroup -SearchString $config.dsg.adminSecurityGroupName )[0].Id -PermissionsToKeys Get, List, Update, Create, Import, Delete, Backup, Restore, Recover -PermissionsToSecrets Get, List, Set, Delete, Recover, Backup, Restore -PermissionsToCertificates Get, List, Delete, Create, Import, Update, Managecontacts, Getissuers, Listissuers, Setissuers, Deleteissuers, Manageissuers, Recover, Backup, Restore
Remove-AzKeyVaultAccessPolicy -VaultName $config.dsg.keyVault.name -UserPrincipalName (Get-AzContext).Account.Id

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;

