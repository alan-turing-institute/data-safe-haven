param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$gitlabAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.adminPasswordSecretName -DefaultLength 20
$gitlabRootPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.rootPasswordSecretName -DefaultLength 20
# $gitlabLdapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.ldapSearch.gitlab.passwordSecretName -DefaultLength 20
$hackmdAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.hackmd.adminPasswordSecretName -DefaultLength 20
# $hackmdLdapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.ldapSearch.hackmd.passwordSecretName -DefaultLength 20
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$ldapSearchUserDn = "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)"
$ldapSearchUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20


# Set up the NSG for the webapps
# ------------------------------
$nsg = Deploy-NetworkSecurityGroup -Name $config.sre.webapps.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "OutboundInternetAccess" `
                             -Description "Outbound internet access" `
                             -Priority 4000 `
                             -Direction Outbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix VirtualNetwork `
                             -SourcePortRange * `
                             -DestinationAddressPrefix Internet `
                             -DestinationPortRange *


# Expand GitLab cloudinit
# -----------------------
$shmDcFqdn = "$($config.shm.dc.hostname).$($config.shm.domain.fqdn)"
$gitlabFqdn = "$($config.sre.webapps.gitlab.hostname).$($config.sre.domain.fqdn)"
# $gitlabLdapUserDn = "CN=$($config.sre.users.computerManagers.gitlab.name),$($config.shm.domain.ous.serviceAccounts.path)"
$gitlabUserFilter = "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path)))"
$gitlabCloudInitTemplate = Join-Path $PSScriptRoot  ".." "cloud_init" "cloud-init-gitlab.template.yaml" | Get-Item | Get-Content -Raw
$gitlabCloudInit = $gitlabCloudInitTemplate.Replace('<gitlab-rb-host>', $shmDcFqdn).
                                            Replace('<gitlab-rb-bind-dn>', $ldapSearchUserDn).
                                            Replace('<gitlab-rb-pw>', $ldapSearchUserPassword).
                                            Replace('<gitlab-rb-base>', $config.shm.domain.ous.researchUsers.path).
                                            Replace('<gitlab-rb-user-filter>', $gitlabUserFilter).
                                            Replace('<gitlab-ip>', $config.sre.webapps.gitlab.ip).
                                            Replace('<gitlab-hostname>', $config.sre.webapps.gitlab.hostname).
                                            Replace('<gitlab-fqdn>', $gitlabFqdn).
                                            Replace('<gitlab-root-password>', $gitlabRootPassword).
                                            Replace('<gitlab-login-domain>', $config.shm.domain.fqdn)
# Encode as base64
$gitlabCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($gitlabCloudInit))


# Expand HackMD cloudinit
# -----------------------
$hackmdFqdn = $config.sre.webapps.hackmd.hostname + "." + $config.sre.domain.fqdn
$hackmdUserFilter = "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path))(userPrincipalName={{username}}))"
# $hackmdSearchLdapUserDn = "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)"
$hackMdLdapUrl = "ldap://$($config.shm.dc.fqdn)"
$hackmdCloudInitTemplate = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-hackmd.template.yaml" | Get-Item | Get-Content -Raw
$hackmdCloudInit = $hackmdCloudInitTemplate.Replace('<hackmd-bind-dn>', $ldapSearchUserDn).
                                            Replace('<hackmd-bind-creds>', $ldapSearchUserPassword).
                                            Replace('<hackmd-user-filter>', $hackmdUserFilter).
                                            Replace('<hackmd-ldap-base>', $config.shm.domain.ous.researchUsers.path).
                                            Replace('<hackmd-ip>', $config.sre.webapps.hackmd.ip).
                                            Replace('<hackmd-hostname>', $config.sre.webapps.hackmd.hostname).
                                            Replace('<hackmd-fqdn>', $hackmdFqdn).
                                            Replace('<hackmd-ldap-url>', $hackMdLdapUrl).
                                            Replace('<hackmd-ldap-netbios>', $config.shm.domain.netbiosName)
# Encode as base64
$hackmdCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($hackmdCloudInit))


# Create webapps resource group
# --------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.webapps.rg -Location $config.sre.location


# Deploy GitLab/HackMD VMs from template
# --------------------------------------
Add-LogMessage -Level Info "Deploying GitLab/HackMD VMs from template..."
$params = @{
    Administrator_User             = $vmAdminUsername
    BootDiagnostics_Account_Name   = $config.sre.storage.bootdiagnostics.accountName
    GitLab_Cloud_Init              = $gitlabCloudInitEncoded
    GitLab_Administrator_Password  = (ConvertTo-SecureString $gitlabAdminPassword -AsPlainText -Force)
    GitLab_Data_Disk_Size_GB       = [int]$config.sre.webapps.gitlab.disks.data.sizeGb
    GitLab_Data_Disk_Type          = $config.sre.webapps.gitlab.disks.data.type
    GitLab_Os_Disk_Size_GB         = [int]$config.sre.webapps.gitlab.disks.os.sizeGb
    GitLab_Os_Disk_Type            = $config.sre.webapps.gitlab.disks.os.type
    GitLab_IP_Address              = $config.sre.webapps.gitlab.ip
    GitLab_Server_Name             = $config.sre.webapps.gitlab.vmName
    GitLab_VM_Size                 = $config.sre.webapps.gitlab.vmSize
    HackMD_Administrator_Password  = (ConvertTo-SecureString $hackmdAdminPassword -AsPlainText -Force)
    HackMD_Cloud_Init              = $hackmdCloudInitEncoded
    HackMD_IP_Address              = $config.sre.webapps.hackmd.ip
    HackMD_Os_Disk_Size_GB         = [int]$config.sre.webapps.hackmd.disks.os.sizeGb
    HackMD_Os_Disk_Type            = $config.sre.webapps.hackmd.disks.os.type
    HackMD_Server_Name             = $config.sre.webapps.hackmd.vmName
    HackMD_VM_Size                 = $config.sre.webapps.hackmd.vmSize
    Virtual_Network_Name           = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet         = $config.sre.network.vnet.subnets.data.name
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
    Add-VmToNSG -VMName $vmName -VmResourceGroupName $config.sre.webapps.rg -NSGName $nsg.Name -NsgResourceGroupName $config.sre.network.vnet.rg
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
$null = Set-AzContext -Context $originalContext;
