param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Make sure terms for gitlab-ce are accepted
Get-AzMarketplaceTerms -Publisher gitlab -Product gitlab-ce -Name gitlab-ce |  Set-AzMarketplaceTerms -Accept

# Admin user credentials (must be same as for DSG DC for now)
$adminUser = $config.dsg.dc.admin.username
$adminPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.dc.admin.passwordSecretName).SecretValueText

# VM sizes
$hackMdVmSize = "Standard_DS2_v2"
$gitlabVmSize = "Standard_DS2_v2"

# Patch cloud init templates
$shmDcFqdn = ($config.shm.dc.hostname + "." + $config.shm.domain.fqdn)
## -- GITLAB --
$gitlabFqdn = $config.dsg.linux.gitlab.hostname + "." + $config.dsg.domain.fqdn
$gitlabLdapUserDn = "CN=" + $config.dsg.users.ldap.gitlab.name + "," + $config.shm.domain.serviceOuPath
$gitlabUserPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.gitlab.passwordSecretName).SecretValueText;
$gitlabUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
# Fetch Gitlab root user password (or create if not present)
$gitlabRootPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.linux.gitlab.rootPasswordSecretName).SecretValueText;
if ($null -eq $gitlabRootPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.linux.gitlab.rootPasswordSecretName -SecretValue $newPassword;
  $gitlabRootPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.linux.gitlab.rootPasswordSecretName).SecretValueText;
}
## Read gitlab template cloud-init file
$gitlabCloudInitTemplatePath = Join-Path $PSScriptRoot "cloud-init-gitlab.yaml"
$gitlabCloudInitTemplate = (Get-Content -Raw -Path $gitlabCloudInitTemplatePath)
## Patch template with DSG specific values
$gitlabCloudInit = $gitlabCloudInitTemplate.replace('<gitlab-rb-host>', $shmDcFqdn).
                                            replace('<gitlab-rb-bind-dn>', $gitlabLdapUserDn).
                                            replace('<gitlab-rb-pw>',$gitlabUserPassword).
                                            replace('<gitlab-rb-base>',$config.shm.domain.userOuPath).
                                            replace('<gitlab-rb-user-filter>',$gitlabUserFilter).
                                            replace('<gitlab-ip>',$config.dsg.linux.gitlab.ip).
                                            replace('<gitlab-hostname>',$config.dsg.linux.gitlab.hostname).
                                            replace('<gitlab-fqdn>',$gitlabFqdn).
                                            replace('<gitlab-root-password>',$gitlabRootPassword).
                                            replace('<gitlab-login-domain>',$config.shm.domain.fqdn)
## Encode as base64
$gitlabCustomData = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($gitlabCloudInit))

## --HACKMD--
$hackmdFqdn = $config.dsg.linux.hackmd.hostname + "." + $config.dsg.domain.fqdn
$hackmdUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + ")(userPrincipalName={{username}}))"
$hackmdUserPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.hackmd.passwordSecretName).SecretValueText;
$hackmdLdapUserDn = "CN=" + $config.dsg.users.ldap.hackmd.name + "," + $config.shm.domain.serviceOuPath
$hackMdLdapUrl = "ldap://" + $config.shm.dc.fqdn
## Read hackmd template cloud-init file
$hackmdCloudInitTemplatePath = Join-Path $PSScriptRoot "cloud-init-hackmd.yaml"
$hackmdCloudInitTemplate = (Get-Content -Raw -Path $hackmdCloudInitTemplatePath)
## Patch template with DSG specific values
$hackmdCloudInit = $hackmdCloudInitTemplate.replace('<hackmd-bind-dn>', $hackmdLdapUserDn).
                                            replace('<hackmd-bind-creds>', $hackmdUserPassword).
                                            replace('<hackmd-user-filter>',$hackmdUserFilter).
                                            replace('<hackmd-ldap-base>',$config.shm.domain.userOuPath).
                                            replace('<hackmd-ip>',$config.dsg.linux.hackmd.ip).
                                            replace('<hackmd-hostname>',$config.dsg.linux.hackmd.hostname).
                                            replace('<hackmd-fqdn>',$hackmdFqdn).
                                            replace('<hackmd-ldap-url>',$hackMdLdapUrl).
                                            replace('<hackmd-ldap-bios>',$config.shm.domain.netbiosName)
# .replace('<gitlab-root-password>',$gitlabRootPassword)
# .replace('<gitlab-login-domain>',$config.shm.domain.fqdn)
## Encode as base64
$hackmdCustomData = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($hackmdCloudInit))

$params = @{
"GITLab Server Name" = $config.dsg.linux.gitlab.vmName
"GITLab VM Size" = $gitlabVMSize
"GITLab IP Address" =  $config.dsg.linux.gitlab.ip 
"HACKMD Server Name" = $config.dsg.linux.hackmd.vmName
"HACKMD VM Size" = $hackmdVMSize
"HACKMD IP Address" = $config.dsg.linux.hackmd.ip
"Administrator User" = $adminUser
"Administrator Password" = (ConvertTo-SecureString $adminPassword -AsPlainText -Force)
"Virtual Network Name" = $config.dsg.network.vnet.name
"Virtual Network Resource Group" = $config.dsg.network.vnet.rg
"Virtual Network Subnet" = $config.dsg.network.subnets.data.name
    "gitlabCustomData" = $gitlabCustomData
    "hackmdCustomData" = $hackmdCustomData
}

Write-Output $params
Write-Output "--------"
Write-Output $gitlabCloudInit
Write-Output "--------"
Write-Output $hackmdCloudInit

$templatePath = Join-Path $PSScriptRoot "linux-master-template.json"

New-AzResourceGroup -Name $config.dsg.linux.rg -Location $config.dsg.location
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.linux.rg `
  -TemplateFile $templatePath @params -Verbose

# Switch back to original subscription
Set-AzContext -Context $prevContext;
