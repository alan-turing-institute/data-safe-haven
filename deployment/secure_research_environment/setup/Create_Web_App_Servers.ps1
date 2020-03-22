param(
    [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE_ID (a short string) e.g 'sandbox' for the sandbox environment")]
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


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword
$gitlabRootPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabRootPassword
$gitlabUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabUserPassword
$gitlabLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabLdapPassword
$hackmdUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.hackmdUserPassword
$hackmdLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.hackmdLdapPassword


# Set up the NSG for the webapps
# ------------------------------
$nsg = Deploy-NetworkSecurityGroup -Name $config.sre.webapps.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "OutboundDenyInternet" `
                             -Description "Outbound deny internet" `
                             -Priority 4000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix Internet -DestinationPortRange *


# Expand GitLab cloudinit
# -----------------------
$shmDcFqdn = ($config.shm.dc.hostname + "." + $config.shm.domain.fqdn)
$gitlabFqdn = $config.sre.webapps.gitlab.hostname + "." + $config.sre.domain.fqdn
$gitlabLdapUserDn = "CN=" + $config.sre.users.ldap.gitlab.name + "," + $config.shm.domain.serviceOuPath
$gitlabUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
$gitlabCloudInitTemplate = Join-Path $PSScriptRoot  ".." "cloud_init" "cloud-init-gitlab.template.yaml" | Get-Item | Get-Content -Raw
$gitlabCloudInit = $gitlabCloudInitTemplate.Replace('<gitlab-rb-host>', $shmDcFqdn).
                                            Replace('<gitlab-rb-bind-dn>', $gitlabLdapUserDn).
                                            Replace('<gitlab-rb-pw>',$gitlabLdapPassword).
                                            Replace('<gitlab-rb-base>',$config.shm.domain.userOuPath).
                                            Replace('<gitlab-rb-user-filter>',$gitlabUserFilter).
                                            Replace('<gitlab-ip>',$config.sre.webapps.gitlab.ip).
                                            Replace('<gitlab-hostname>',$config.sre.webapps.gitlab.hostname).
                                            Replace('<gitlab-fqdn>',$gitlabFqdn).
                                            Replace('<gitlab-root-password>',$gitlabRootPassword).
                                            Replace('<gitlab-login-domain>',$config.shm.domain.fqdn)
# Encode as base64
$gitlabCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($gitlabCloudInit))


# Expand HackMD cloudinit
# -----------------------
$hackmdFqdn = $config.sre.webapps.hackmd.hostname + "." + $config.sre.domain.fqdn
$hackmdUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + ")(userPrincipalName={{username}}))"
$hackmdLdapUserDn = "CN=" + $config.sre.users.ldap.hackmd.name + "," + $config.shm.domain.serviceOuPath
$hackMdLdapUrl = "ldap://" + $config.shm.dc.fqdn
$hackmdCloudInitTemplate = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-hackmd.template.yaml" | Get-Item | Get-Content -Raw
$hackmdCloudInit = $hackmdCloudInitTemplate.Replace('<hackmd-bind-dn>', $hackmdLdapUserDn).
                                            Replace('<hackmd-bind-creds>', $hackmdLdapPassword).
                                            Replace('<hackmd-user-filter>',$hackmdUserFilter).
                                            Replace('<hackmd-ldap-base>',$config.shm.domain.userOuPath).
                                            Replace('<hackmd-ip>',$config.sre.webapps.hackmd.ip).
                                            Replace('<hackmd-hostname>',$config.sre.webapps.hackmd.hostname).
                                            Replace('<hackmd-fqdn>',$hackmdFqdn).
                                            Replace('<hackmd-ldap-url>',$hackMdLdapUrl).
                                            Replace('<hackmd-ldap-netbios>',$config.shm.domain.netbiosName)
# Encode as base64
$hackmdCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($hackmdCloudInit))


# Create webapps resource group
# --------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.webapps.rg -Location $config.sre.location


# Deploy GitLab/HackMD VMs from template
# --------------------------------------
Add-LogMessage -Level Info "Deploying GitLab/HackMD VMs from template..."
$params = @{
    Administrator_Password = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    Administrator_User = $dcAdminUsername
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    GitLab_Cloud_Init = $gitlabCloudInitEncoded
    GitLab_IP_Address =  $config.sre.webapps.gitlab.ip
    GitLab_Server_Name = $config.sre.webapps.gitlab.vmName
    GitLab_VM_Size = $config.sre.webapps.gitlab.vmSize
    HackMD_Cloud_Init = $hackmdCloudInitEncoded
    HackMD_IP_Address = $config.sre.webapps.hackmd.ip
    HackMD_Server_Name = $config.sre.webapps.hackmd.vmName
    HackMD_VM_Size = $config.sre.webapps.hackmd.vmSize
    Virtual_Network_Name = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.data.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-webapps-template.json") -Params $params -ResourceGroupName $config.sre.webapps.rg


# Poll VMs to see when they have finished running
# -----------------------------------------------
Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
$progress = 0
$gitlabStatuses = (Get-AzVM -Name $config.sre.webapps.gitlab.vmName -ResourceGroupName $config.sre.webapps.rg -Status).Statuses.Code
$hackmdStatuses = (Get-AzVM -Name $config.sre.webapps.hackmd.vmName -ResourceGroupName $config.sre.webapps.rg -Status).Statuses.Code
while (-Not ($gitlabStatuses.Contains("ProvisioningState/succeeded") -and $gitlabStatuses.Contains("PowerState/stopped") -and
             $hackmdStatuses.Contains("ProvisioningState/succeeded") -and $hackmdStatuses.Contains("PowerState/stopped"))) {
    $progress = [math]::min(100, $progress + 1)
    $gitlabStatuses = (Get-AzVM -Name $config.sre.webapps.gitlab.vmName -ResourceGroupName $config.sre.webapps.rg -Status).Statuses.Code
    $hackmdStatuses = (Get-AzVM -Name $config.sre.webapps.hackmd.vmName -ResourceGroupName $config.sre.webapps.rg -Status).Statuses.Code
    Write-Progress -Activity "Deployment status:" -Status "GitLab [$($gitlabStatuses[0]) $($gitlabStatuses[1])], HackMD [$($hackmdStatuses[0]) $($hackmdStatuses[1])]" -PercentComplete $progress
    Start-Sleep 10
}


# While webapp servers are off, ensure they are bound to correct NSG
# ------------------------------------------------------------------
Add-LogMessage -Level Info "Ensure webapp servers and compute VMs are bound to correct NSG..."
foreach ($vmName in ($config.sre.webapps.hackmd.vmName, $config.sre.webapps.gitlab.vmName)) {
    Add-VmToNSG -VMName $vmName -NSGName $nsg.Name
}
Start-Sleep -Seconds 30
Add-LogMessage -Level Info "Summary: NICs associated with '$($nsg.Name)' NSG"
@($nsg.NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }


# Finally, reboot the webapp servers
# ----------------------------------
foreach ($nameVMNameParamsPair in (("HackMD", $config.sre.webapps.hackmd.vmName), ("GitLab", $config.sre.webapps.gitlab.vmName))) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Rebooting the $name VM: '$vmName'"
    Enable-AzVM -Name $vmName -ResourceGroupName $config.sre.webapps.rg
    if ($?) {
        Add-LogMessage -Level Success "Rebooting the $name VM ($vmName) succeeded"
    } else {
        Add-LogMessage -Level Fatal "Rebooting the $name VM ($vmName) failed!"
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
