param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE_ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Make sure terms for gitlab-ce are accepted
# ------------------------------------------
$_ = Get-AzMarketplaceTerms -Publisher gitlab -Product gitlab-ce -Name gitlab-ce |  Set-AzMarketplaceTerms -Accept


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword
$gitlabRootPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabRootPassword
$gitlabUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabUserPassword
$hackmdUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.hackmdUserPassword


# Patch GitLab_Cloud_Init
# -----------------------
$shmDcFqdn = ($config.shm.dc.hostname + "." + $config.shm.domain.fqdn)
$gitlabFqdn = $config.sre.linux.gitlab.hostname + "." + $config.sre.domain.fqdn
$gitlabLdapUserDn = "CN=" + $config.sre.users.ldap.gitlab.name + "," + $config.shm.domain.serviceOuPath
$gitlabUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
$gitlabCloudInitTemplate = Join-Path $PSScriptRoot "templates" "cloud-init-gitlab.template.yaml" | Get-Item | Get-Content -Raw
$gitlabCloudInit = $gitlabCloudInitTemplate.replace('<gitlab-rb-host>', $shmDcFqdn).
                                            replace('<gitlab-rb-bind-dn>', $gitlabLdapUserDn).
                                            replace('<gitlab-rb-pw>',$gitlabUserPassword).
                                            replace('<gitlab-rb-base>',$config.shm.domain.userOuPath).
                                            replace('<gitlab-rb-user-filter>',$gitlabUserFilter).
                                            replace('<gitlab-ip>',$config.sre.linux.gitlab.ip).
                                            replace('<gitlab-hostname>',$config.sre.linux.gitlab.hostname).
                                            replace('<gitlab-fqdn>',$gitlabFqdn).
                                            replace('<gitlab-root-password>',$gitlabRootPassword).
                                            replace('<gitlab-login-domain>',$config.shm.domain.fqdn)
# Encode as base64
$gitlabCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($gitlabCloudInit))


# Patch HackMD_Cloud_Init
# -----------------------
$hackmdFqdn = $config.sre.linux.hackmd.hostname + "." + $config.sre.domain.fqdn
$hackmdUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + ")(userPrincipalName={{username}}))"
$hackmdLdapUserDn = "CN=" + $config.sre.users.ldap.hackmd.name + "," + $config.shm.domain.serviceOuPath
$hackMdLdapUrl = "ldap://" + $config.shm.dc.fqdn
$hackmdCloudInitTemplate = Join-Path $PSScriptRoot "templates" "cloud-init-hackmd.template.yaml" | Get-Item | Get-Content -Raw
$hackmdCloudInit = $hackmdCloudInitTemplate.replace('<hackmd-bind-dn>', $hackmdLdapUserDn).
                                            replace('<hackmd-bind-creds>', $hackmdUserPassword).
                                            replace('<hackmd-user-filter>',$hackmdUserFilter).
                                            replace('<hackmd-ldap-base>',$config.shm.domain.userOuPath).
                                            replace('<hackmd-ip>',$config.sre.linux.hackmd.ip).
                                            replace('<hackmd-hostname>',$config.sre.linux.hackmd.hostname).
                                            replace('<hackmd-fqdn>',$hackmdFqdn).
                                            replace('<hackmd-ldap-url>',$hackMdLdapUrl).
                                            replace('<hackmd-ldap-netbios>',$config.shm.domain.netbiosName)
# Encode as base64
$hackmdCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($hackmdCloudInit))


# Set up the NSG for the webapps
# ------------------------------
$nsgWebapps = Deploy-NetworkSecurityGroup -Name $config.sre.linux.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgWebapps `
                             -Name "Internet_Out" `
                             -Description "Deny Outbound Internet Access" `
                             -Priority 4000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix Internet -DestinationPortRange *


# Create webapps resource group
# --------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.linux.rg -Location $config.sre.location


# Deploy GitLab/HackMD VMs from template
# --------------------------------------
Add-LogMessage -Level Info "Deploying GitLab/HackMD VMs from template..."
$params = @{
    Administrator_Password = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    Administrator_User = $dcAdminUsername
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    GitLab_Cloud_Init = $gitlabCloudInitEncoded
    GitLab_IP_Address =  $config.sre.linux.gitlab.ip
    GitLab_Server_Name = $config.sre.linux.gitlab.vmName
    GitLab_VM_Size = $config.sre.linux.gitlab.vmSize
    HackMD_Cloud_Init = $hackmdCloudInitEncoded
    HackMD_IP_Address = $config.sre.linux.hackmd.ip
    HackMD_Server_Name = $config.sre.linux.hackmd.vmName
    HackMD_VM_Size = $config.sre.linux.hackmd.vmSize
    Virtual_Network_Name = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.data.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot "sre-webapps-template.json") -Params $params -ResourceGroupName $config.sre.linux.rg


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
