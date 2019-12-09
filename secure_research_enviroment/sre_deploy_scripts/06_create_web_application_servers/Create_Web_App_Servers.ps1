param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# Get SRE config
# --------------
$config = Get-SreConfig($sreId);
$originalContext = Get-AzContext


# Make sure terms for gitlab-ce are accepted
# ------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$_ = Get-AzMarketplaceTerms -Publisher gitlab -Product gitlab-ce -Name gitlab-ce |  Set-AzMarketplaceTerms -Accept


# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving secrets from '$($config.dsg.keyVault.name)' KeyVault..."
$dcAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()
$dcAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminPassword
$gitlabRootPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.gitlabRootPassword
$gitlabUserPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.gitlabUserPassword
$hackmdUserPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.hackmdUserPassword


# Patch GitLab cloud init
# -----------------------
$shmDcFqdn = ($config.shm.dc.hostname + "." + $config.shm.domain.fqdn)
$gitlabFqdn = $config.dsg.linux.gitlab.hostname + "." + $config.dsg.domain.fqdn
$gitlabLdapUserDn = "CN=" + $config.dsg.users.ldap.gitlab.name + "," + $config.shm.domain.serviceOuPath
$gitlabUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
$gitlabCloudInitTemplate = Join-Path $PSScriptRoot "templates" "cloud-init-gitlab.template.yaml" | Get-Item | Get-Content -Raw
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
# Encode as base64
$gitlabCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($gitlabCloudInit))


# Patch HackMD cloud init
# -----------------------
$hackmdFqdn = $config.dsg.linux.hackmd.hostname + "." + $config.dsg.domain.fqdn
$hackmdUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + ")(userPrincipalName={{username}}))"
$hackmdLdapUserDn = "CN=" + $config.dsg.users.ldap.hackmd.name + "," + $config.shm.domain.serviceOuPath
$hackMdLdapUrl = "ldap://" + $config.shm.dc.fqdn
$hackmdCloudInitTemplate = Join-Path $PSScriptRoot "templates" "cloud-init-hackmd.template.yaml" | Get-Item | Get-Content -Raw
$hackmdCloudInit = $hackmdCloudInitTemplate.replace('<hackmd-bind-dn>', $hackmdLdapUserDn).
                                            replace('<hackmd-bind-creds>', $hackmdUserPassword).
                                            replace('<hackmd-user-filter>',$hackmdUserFilter).
                                            replace('<hackmd-ldap-base>',$config.shm.domain.userOuPath).
                                            replace('<hackmd-ip>',$config.dsg.linux.hackmd.ip).
                                            replace('<hackmd-hostname>',$config.dsg.linux.hackmd.hostname).
                                            replace('<hackmd-fqdn>',$hackmdFqdn).
                                            replace('<hackmd-ldap-url>',$hackMdLdapUrl).
                                            replace('<hackmd-ldap-netbios>',$config.shm.domain.netbiosName)
# Encode as base64
$hackmdCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($hackmdCloudInit))


# Deploy GitLab/HackMD VMs from template
# --------------------------------------
Write-Host -ForegroundColor DarkCyan "Deploying GitLab/HackMD VMs from template..."
$_ = New-AzResourceGroup -Name $config.dsg.linux.rg -Location $config.dsg.location -Force
$templateName = "sre-webapps-template"
$params = @{
    "SRE ID" = $config.dsg.id
    "GitLab Server Name" = $config.dsg.linux.gitlab.vmName
    "GitLab VM Size" = $config.dsg.linux.gitlab.vmSize
    "GitLab IP Address" =  $config.dsg.linux.gitlab.ip
    "GitLab Cloud Init" = $gitlabCloudInitEncoded
    "HackMD Server Name" = $config.dsg.linux.hackmd.vmName
    "HackMD VM Size" = $config.dsg.linux.hackmd.vmSize
    "HackMD IP Address" = $config.dsg.linux.hackmd.ip
    "HackMD Cloud Init" = $hackmdCloudInitEncoded
    "Administrator User" = $dcAdminUsername
    "Administrator Password" = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    "NSG Name" = $config.dsg.linux.nsg
    "Virtual Network Name" = $config.dsg.network.vnet.name
    "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
    "Virtual Network Subnet" = $config.dsg.network.subnets.data.name
}
# Deploy webapp template
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.linux.rg -TemplateFile $(Join-Path $PSScriptRoot "$($templateName).json") @params -Verbose -DeploymentDebugLogLevel ResponseContent
$result = $?
LogTemplateOutput -ResourceGroupName $config.dsg.linux.rg -DeploymentName $templateName
if ($result) {
    Write-Host -ForegroundColor DarkGreen " [o] Template deployment succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Template deployment failed!"
    throw "Template deployment has failed. Please check the error message above before re-running this script."
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
