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
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.webappAdminPassword
$gitlabRootPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabRootPassword
$gitlabUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabUserPassword
$gitlabLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabLdapPassword
$gitlabReviewUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabReviewUsername -DefaultValue "ingress"
$gitlabReviewPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabReviewPassword
$gitlabReviewAPIToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabReviewAPIToken
$hackmdPostgresPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.hackmdUserPassword
$hackmdLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.hackmdLdapPassword
$gitlabUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabUsername -DefaultValue "ingress"
$gitlabPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabPassword
$gitlabAPIToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.gitlabAPIToken


# Set up NSGs for the webapps
# ---------------------------
$nsgWebapps = Deploy-NetworkSecurityGroup -Name $config.sre.webapps.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgWebapps `
                             -Name "OutboundDenyInternet" `
                             -Description "Outbound deny internet" `
                             -Priority 4000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix Internet -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgAirlock `
                             -Name "OutboundDenyVNet" `
                             -Description "Outbound deny VNet connections" `
                             -Priority 3000 `
                             -Direction Inbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix VirtualNetwork -DestinationPortRange *
$nsgAirlock = Deploy-NetworkSecurityGroup -Name $config.sre.network.nsg.airlock.name -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgAirlock `
                             -Name "InboundAllowReviewServer" `
                             -Description "Inbound allow connections from review session host" `
                             -Priority 2000 `
                             -Direction Inbound -Access Allow -Protocol * `
                             -SourceAddressPrefix $config.sre.rds.sessionHost3.ip -SourcePortRange * `
                             -DestinationAddressPrefix VirtualNetwork -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgAirlock `
                             -Name "InboundAllowVpnSsh" `
                             -Description "Inbound allow SSH connections from VPN subnet" `
                             -Priority 3000 `
                             -Direction Inbound -Access Allow -Protocol TCP `
                             -SourceAddressPrefix "172.16.201.0/24" -SourcePortRange * `  # TODO fix this when this is no longer hard-coded
                             -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 22
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgAirlock `
                             -Name "InboundDenyOtherVNet" `
                             -Description "Inbound deny other VNet connections" `
                             -Priority 4000 `
                             -Direction Inbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix VirtualNetwork -DestinationPortRange *


# Check that VNET and subnets exist
# ---------------------------------
$vnet = Deploy-VirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -AddressPrefix $config.sre.network.vnet.cidr -Location $config.sre.location
$null = Deploy-Subnet -Name $config.sre.network.subnets.data.name -VirtualNetwork $vnet -AddressPrefix $config.sre.network.subnets.data.cidr
$airlockSubnet = Deploy-Subnet -Name $config.sre.network.subnets.airlock.name -VirtualNetwork $vnet -AddressPrefix $config.sre.network.subnets.airlock.cidr


# Expand GitLab cloudinit
# -----------------------
$shmDcFqdn = ($config.shm.dc.hostname + "." + $config.shm.domain.fqdn)
$gitlabFqdn = $config.sre.webapps.gitlab.hostname + "." + $config.sre.domain.fqdn
$gitlabLdapUserDn = "CN=" + $config.sre.users.ldap.gitlab.name + "," + $config.shm.domain.serviceOuPath
$gitlabUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
$gitlabCloudInitTemplate = Join-Path $PSScriptRoot  ".." "cloud_init" "cloud-init-gitlab.template.yaml" | Get-Item | Get-Content -Raw
$gitlabCloudInit = $gitlabCloudInitTemplate.Replace('<gitlab-rb-host>', $shmDcFqdn).
                                            Replace('<gitlab-rb-bind-dn>', $gitlabLdapUserDn).
                                            Replace('<gitlab-rb-pw>', $gitlabLdapPassword).
                                            Replace('<gitlab-rb-base>', $config.shm.domain.userOuPath).
                                            Replace('<gitlab-rb-user-filter>', $gitlabUserFilter).
                                            Replace('<gitlab-ip>', $config.sre.webapps.gitlab.ip).
                                            Replace('<gitlab-hostname>', $config.sre.webapps.gitlab.hostname).
                                            Replace('<gitlab-fqdn>', $gitlabFqdn).
                                            Replace('<gitlab-root-password>', $gitlabRootPassword).
                                            Replace('<gitlab-login-domain>', $config.shm.domain.fqdn).
                                            Replace('<gitlab-username>', $gitlabUsername).
                                            Replace('<gitlab-password>', $gitlabPassword).
                                            Replace('<gitlab-api-token>', $gitlabAPIToken)
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
                                            Replace('<hackmd-ldap-base>', $config.shm.domain.userOuPath).
                                            Replace('<hackmd-ip>', $config.sre.webapps.hackmd.ip).
                                            Replace('<hackmd-hostname>', $config.sre.webapps.hackmd.hostname).
                                            Replace('<hackmd-fqdn>', $hackmdFqdn).
                                            Replace('<hackmd-ldap-url>', $hackMdLdapUrl).
                                            Replace('<hackmd-ldap-netbios>', $config.shm.domain.netbiosName).
                                            Replace('<hackmd-postgres-password>', $hackmdPostgresPassword)
# Encode as base64
$hackmdCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($hackmdCloudInit))


# Create webapps resource group
# --------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.webapps.rg -Location $config.sre.location


# Deploy GitLab/HackMD VMs from template
# --------------------------------------
Add-LogMessage -Level Info "Deploying GitLab/HackMD VMs from template..."
$params = @{
    Administrator_Password = (ConvertTo-SecureString $sreAdminPassword -AsPlainText -Force)
    Administrator_User = $sreAdminUsername
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
    Add-VmToNSG -VMName $vmName -NSGName $nsgWebapps.Name
}


# Reboot the HackMD and Gitlab servers
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


# Get public SSH keys from the GitLab server
# This allows it to be added as a known host on the GitLab review server
# ----------------------------------------------------------------------
$script = '
#! /bin/bash
echo "<gitlab-ip> $(cat /etc/ssh/ssh_host_rsa_key.pub | cut -d " " -f -2)"
echo "<gitlab-ip> $(cat /etc/ssh/ssh_host_ed25519_key.pub | cut -d " " -f -2)"
echo "<gitlab-ip> $(cat /etc/ssh/ssh_host_ecdsa_key.pub | cut -d " " -f -2)"
'.Replace('<gitlab-ip>', $config.sre.webapps.gitlab.ip)
$result = Invoke-RemoteScript -VMName $config.sre.webapps.gitlab.vmName -ResourceGroupName $config.sre.webapps.rg -Shell "UnixShell" -Script $script
Add-LogMessage -Level Success "Fetching ssh keys from gitlab succeeded"
# Extract everything in between the [stdout] and [stderr] blocks of the result message. i.e. all output of the script.
$sshKeys = $result.Value[0].Message | Select-String "\[stdout\]\s*([\s\S]*?)\s*\[stderr\]"
# $sshKeys = $sshKeys.Matches.Groups[1].Value


# Deploy NIC and data disks for GitLab review server
# --------------------------------------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$vmNameReview = $config.sre.webapps.gitlabreview.vmName
$vmIpAddress = $config.sre.webapps.gitlabreview.ip
$vmNic = Deploy-VirtualMachineNIC -Name "$vmNameReview-NIC" -ResourceGroupName $config.sre.webapps.rg -Subnet $subnet -PrivateIpAddress $vmIpAddress -Location $config.sre.location


# Expand GitLab review cloudinit
# ------------------------------
$gitlabReviewCloudInitTemplate = Join-Path $PSScriptRoot  ".." "cloud_init" "cloud-init-gitlab-review.template.yaml" | Get-Item | Get-Content -Raw
$gitlabReviewFqdn = $config.sre.webapps.gitlabreview.hostname + "." + $config.sre.domain.fqdn
$gitlabReviewLdapUserDn = "CN=" + $config.sre.users.ldap.gitlab.name + "," + $config.shm.domain.serviceOuPath
$gitlabReviewUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.reviewUsers.name + "," + $config.shm.domain.securityOuPath + "))"

# Insert SSH keys and scripts into cloud init template, maintaining indentation
$indent = "      "
foreach ($scriptName in @("zipfile_to_gitlab_project.py",
                          "check_merge_requests.py",
                          "gitlab_config.py",
                          "gitlab-ssh-keys")) {
    if ($scriptName -eq "gitlab-ssh-keys") {
        $raw_script = $sshKeys.Matches.Groups[1].Value
    } else {
        $raw_script = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "scripts" $scriptName) -Raw
    }
    $indented_script = $raw_script -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $gitlabReviewCloudInitTemplate = $gitlabReviewCloudInitTemplate.Replace("${indent}<$scriptName>", $indented_script)
}

# Insert other variables into template
$gitlabReviewCloudInit = $gitlabReviewCloudInitTemplate.Replace('<sre-admin-username>', $sreAdminUsername).
                                                        Replace('<gitlab-ip>', $config.sre.webapps.gitlab.ip).
                                                        Replace('<gitlab-username>', $gitlabUsername).
                                                        Replace('<gitlab-api-token>', $gitlabAPIToken).
                                                        Replace('<gitlab-review-rb-host>', $shmDcFqdn).
                                                        Replace('<gitlab-review-rb-bind-dn>', $gitlabReviewLdapUserDn).
                                                        Replace('<gitlab-review-rb-pw>', $gitlabLdapPassword).
                                                        Replace('<gitlab-review-rb-base>', $config.shm.domain.userOuPath).
                                                        Replace('<gitlab-review-rb-user-filter>', $gitlabReviewUserFilter).
                                                        Replace('<gitlab-review-ip>', $config.sre.webapps.gitlabreview.ip).
                                                        Replace('<gitlab-review-hostname>', $config.sre.webapps.gitlabreview.hostname).
                                                        Replace('<gitlab-review-fqdn>', $gitlabReviewFqdn).
                                                        Replace('<gitlab-review-root-password>', $gitlabRootPassword).
                                                        Replace('<gitlab-review-login-domain>', $config.shm.domain.fqdn).
                                                        Replace('<gitlab-review-username>', $gitlabReviewUsername).
                                                        Replace('<gitlab-review-password>', $gitlabReviewPassword).
                                                        Replace('<gitlab-review-api-token>', $gitlabReviewAPIToken)
# Deploy VM and add to correct NSG when done
$params = @{
    Name = $vmNameReview
    Size = $config.sre.webapps.gitlabreview.vmSize
    AdminPassword = $sreAdminPassword
    AdminUsername = $sreAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml = $gitlabReviewCloudInit
    location = $config.sre.location
    NicId = $vmNic.Id
    OsDiskType = "Standard_LRS"
    ResourceGroupName = $config.sre.webapps.rg
    ImageSku = "18.04-LTS"
}
$_ = Deploy-UbuntuVirtualMachine @params
Wait-ForAzVMCloudInit -Name $vmNameReview -ResourceGroupName $config.sre.webapps.rg
Add-VmToNSG -VMName $vmNameReview -NSGName $nsgAirlock
Enable-AzVM -Name $vmNameReview -ResourceGroupName $config.sre.webapps.rg


# List VMs connected to each NSG
# ------------------------------
foreach ($nsg in @($nsgWebapps, $nsgAirlock)) {
    Add-LogMessage -Level Info "Summary: NICs associated with '$($nsg.Name)' NSG"
    @($nsg.NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
