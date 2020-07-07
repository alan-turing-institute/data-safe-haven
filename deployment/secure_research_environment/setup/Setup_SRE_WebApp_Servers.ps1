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
$gitlabAPIToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.apiTokenSecretName -DefaultLength 20
$gitlabUserIngressPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.userIngress.passwordSecretName -DefaultLength 20
$gitlabUserIngressUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.userIngress.usernameSecretName -DefaultValue "ingress"
$gitlabUserRootPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.userRoot.passwordSecretName -DefaultLength 20
$gitlabReviewAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlabReview.adminPasswordSecretName -DefaultLength 20
$gitlabReviewAPIToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlabReview.apiTokenSecretName -DefaultLength 20
$gitlabReviewUserIngressPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlabReview.userIngress.passwordSecretName -DefaultLength 20
$gitlabReviewUserIngressUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlabReview.userIngress.usernameSecretName -DefaultValue "ingress"
$gitlabReviewUserRootPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlabReview.userRoot.passwordSecretName -DefaultLength 20
$hackmdAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.hackmd.adminPasswordSecretName -DefaultLength 20
$hackmdPostgresPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.hackmd.postgresPasswordSecretName -DefaultLength 20
$ldapSearchUserDn = "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)"
$ldapSearchUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()

# Set up NSGs for the webapps
# ---------------------------
$nsgAirlock = Deploy-NetworkSecurityGroup -Name $config.sre.network.nsg.airlock.name -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location -RemoveAllRules
$nsgWebapps = Deploy-NetworkSecurityGroup -Name $config.sre.webapps.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location -RemoveAllRules
$params = @{
    ipAddressGitLab = $config.sre.webapps.gitlab.ip
    ipAddressGitLabReview = $config.sre.webapps.gitlabReview.ip
    ipAddressSessionHostApps = $config.sre.rds.sessionHost1.ip
    ipAddressSessionHostReview = $config.sre.rds.sessionHost3.ip
    nsgAirlockName = $config.sre.network.nsg.airlock.name
    nsgWebappsName = $config.sre.webapps.nsg
    subnetComputeCidr =  $config.sre.network.vnet.subnets.data.cidr
    subnetVpnCidr = "172.16.201.0/24" # TODO fix this when it is no longer hard-coded
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-nsg-rules-template.json") -Params $params -ResourceGroupName $config.sre.network.vnet.rg


# Check that VNET and subnets exist
# ---------------------------------
$vnet = Deploy-VirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -AddressPrefix $config.sre.network.vnet.cidr -Location $config.sre.location
$subnetAirlock = Deploy-Subnet -Name $config.sre.network.vnet.subnets.airlock.name -VirtualNetwork $vnet -AddressPrefix $config.sre.network.vnet.subnets.airlock.cidr
$subnetWebapps = Deploy-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetwork $vnet -AddressPrefix $config.sre.network.vnet.subnets.data.cidr  # NB. this is currently the SharedData subnet but will change soon


# Attach NSGs to subnets
# ----------------------
$subnetAirlock = Set-SubnetNetworkSecurityGroup -Subnet $subnetAirlock -VirtualNetwork $vnet -NetworkSecurityGroup $nsgAirlock


# Create webapps resource group
# --------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.webapps.rg -Location $config.sre.location


# Construct common deployment parameters
# --------------------------------------
$commonDeploymentParams = @{
    AdminUsername = $vmAdminUsername
    BootDiagnosticsAccount = $(Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location)
    ImageSku = "18.04-LTS"
    Location = $config.sre.location
    OsDiskSizeGb = 64
    OsDiskType = "Standard_LRS"
    ResourceGroupName = $config.sre.webapps.rg
}


# Deploy GitLab
# -------------
# Construct GitLab cloudinit
$gitlabCloudInit = (Join-Path $PSScriptRoot  ".." "cloud_init" "cloud-init-gitlab.template.yaml" | Get-Item | Get-Content -Raw).
    Replace('<gitlab-rb-bind-dn>', $ldapSearchUserDn).
    Replace('<gitlab-rb-pw>', $ldapSearchUserPassword).
    Replace('<gitlab-rb-base>', $config.shm.domain.ous.researchUsers.path).
    Replace('<gitlab-rb-user-filter>', "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.securityOuPath)))").
    Replace('<gitlab-rb-host>', "$($config.shm.dc.hostname).$($config.shm.domain.fqdn)").
    Replace('<gitlab-ip>', $config.sre.webapps.gitlab.ip).
    Replace('<gitlab-hostname>', $config.sre.webapps.gitlab.hostname).
    Replace('<gitlab-fqdn>', "$($config.sre.webapps.gitlab.hostname).$($config.sre.domain.fqdn)").
    Replace('<gitlab-root-password>', $gitlabUserRootPassword).
    Replace('<gitlab-login-domain>', $config.shm.domain.fqdn).
    Replace('<gitlab-username>', $gitlabUserIngressUsername).
    Replace('<gitlab-password>', $gitlabUserIngressPassword).
    Replace('<gitlab-api-token>', $gitlabAPIToken)
# Set GitLab deployment parameters
$gitlabDataDisk = Deploy-ManagedDisk -Name "$($config.sre.webapps.gitlab.vmName)-DATA-DISK" -SizeGB 512 -Type "Standard_LRS" -ResourceGroupName $config.sre.webapps.rg -Location $config.sre.location
$gitlabDeploymentParams = @{
    AdminPassword = $gitlabAdminPassword
    CloudInitYaml = $gitlabCloudInit
    DataDiskIds = @($gitlabDataDisk.Id)
    Name = $config.sre.webapps.gitlab.vmName
    PrivateIpAddress = $config.sre.webapps.gitlab.ip
    Size = $config.sre.webapps.gitlab.vmSize
    Subnet = $subnetWebapps
}
# Deploy GitLab VM
try {
    Add-LogMessage -Level Warning "Temporarily allowing outbound internet access from $($config.sre.webapps.gitlab.ip)..."  # Note that this has no effect at present
    Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgWebapps -Name "TmpAllowOutboundInternetGitlab" -SourceAddressPrefix $config.sre.webapps.gitlab.ip -Access Allow -Description "Allow outbound internet" -DestinationAddressPrefix Internet -DestinationPortRange * -Direction Outbound -Priority 100 -Protocol * -SourcePortRange *
    $null = Deploy-UbuntuVirtualMachine @gitlabDeploymentParams @commonDeploymentParams
    Add-VmToNSG -VMName $config.sre.webapps.gitlab.vmName -NSGName $config.sre.webapps.nsg -VmResourceGroupName $config.sre.webapps.rg -NsgResourceGroupName $config.sre.network.vnet.rg
    Enable-AzVM -Name $config.sre.webapps.gitlab.vmName -ResourceGroupName $config.sre.webapps.rg
} finally {
    $null = Remove-AzNetworkSecurityRuleConfig -Name "TmpAllowOutboundInternetGitlab" -NetworkSecurityGroup $nsgWebapps
}


# Deploy HackMD
# -------------
# Construct HackMD cloudinit
$hackmdCloudInit = (Join-Path $PSScriptRoot  ".." "cloud_init" "cloud-init-hackmd.template.yaml" | Get-Item | Get-Content -Raw).
    Replace('<hackmd-bind-dn>', $ldapSearchUserDn).
    Replace('<hackmd-bind-creds>', $ldapSearchUserPassword).
    Replace('<hackmd-user-filter>', "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.securityOuPath))(userPrincipalName={{username}}))").
    Replace('<hackmd-ldap-base>', $config.shm.domain.ous.researchUsers.path).
    Replace('<hackmd-ip>', $config.sre.webapps.hackmd.ip).
    Replace('<hackmd-hostname>', $config.sre.webapps.hackmd.hostname).
    Replace('<hackmd-fqdn>', "$($config.sre.webapps.hackmd.hostname).$($config.sre.domain.fqdn)").
    Replace('<hackmd-ldap-url>', "ldap://$($config.shm.dc.fqdn)").
    Replace('<hackmd-ldap-netbios>', $config.shm.domain.netbiosName).
    Replace('<hackmd-postgres-password>', $hackmdPostgresPassword)
# Set HackMD deployment parameters
$hackmdDataDisk = Deploy-ManagedDisk -Name "$($config.sre.webapps.hackmd.vmName)-DATA-DISK" -SizeGB 512 -Type "Standard_LRS" -ResourceGroupName $config.sre.webapps.rg -Location $config.sre.location
$hackmdDeploymentParams = @{
    AdminPassword = $hackmdAdminPassword
    CloudInitYaml = $hackmdCloudInit
    DataDiskIds = @($hackmdDataDisk.Id)
    Name = $config.sre.webapps.hackmd.vmName
    PrivateIpAddress = $config.sre.webapps.hackmd.ip
    Size = $config.sre.webapps.hackmd.vmSize
    Subnet = $subnetWebapps
}
# Deploy HackMD VM
try {
    Add-LogMessage -Level Warning "Temporarily allowing outbound internet access from $($config.sre.webapps.hackmd.ip)..."  # Note that this has no effect at present
    Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgWebapps -Name "TmpAllowOutboundInternetHackMD" -SourceAddressPrefix $config.sre.webapps.hackmd.ip -Access Allow -Description "Allow outbound internet" -DestinationAddressPrefix Internet -DestinationPortRange * -Direction Outbound -Priority 100 -Protocol * -SourcePortRange *
    $null = Deploy-UbuntuVirtualMachine @hackmdDeploymentParams @commonDeploymentParams
    Add-VmToNSG -VMName $config.sre.webapps.hackmd.vmName -NSGName $config.sre.webapps.nsg -VmResourceGroupName $config.sre.webapps.rg -NsgResourceGroupName $config.sre.network.vnet.rg
    Enable-AzVM -Name $config.sre.webapps.hackmd.vmName -ResourceGroupName $config.sre.webapps.rg
} finally {
    $null = Remove-AzNetworkSecurityRuleConfig -Name "TmpAllowOutboundInternetHackMD" -NetworkSecurityGroup $nsgWebapps
}


# Deploy GitLab review
# --------------------
# Get public SSH keys from the GitLab server, allowing it to be added as a known host on the GitLab review server
Add-LogMessage -Level Info "Fetching ssh keys from gitlab..."
$script = @"
#! /bin/bash
echo "<gitlab-ip> $(cut -d ' ' -f -2 /etc/ssh/ssh_host_rsa_key.pub)"
echo "<gitlab-ip> $(cut -d ' ' -f -2 /etc/ssh/ssh_host_ed25519_key.pub)"
echo "<gitlab-ip> $(cut -d ' ' -f -2 /etc/ssh/ssh_host_ecdsa_key.pub)"
"@.Replace("<gitlab-ip>", $config.sre.webapps.gitlab.ip)
$result = Invoke-RemoteScript -VMName $config.sre.webapps.gitlab.vmName -ResourceGroupName $config.sre.webapps.rg -Shell "UnixShell" -Script $script
Add-LogMessage -Level Success "Fetching ssh keys from gitlab succeeded"
$sshKeys = $result.Value[0].Message | Select-String "\[stdout\]\s*([\s\S]*?)\s*\[stderr\]"  # Extract everything in between the [stdout] and [stderr] blocks of the result message. i.e. all output of the script.
# Construct GitLab review cloudinit
$gitlabReviewCloudInit = (Join-Path $PSScriptRoot  ".." "cloud_init" "cloud-init-gitlab-review.template.yaml" | Get-Item | Get-Content -Raw).
    Replace('<gitlab-ip>', $config.sre.webapps.gitlab.ip).
    Replace('<gitlab-username>', $gitlabUsername).
    Replace('<gitlab-api-token>', $gitlabAPIToken).
    Replace('<gitlab-review-rb-host>', "$($config.shm.dc.hostname).$($config.shm.domain.fqdn)").
    Replace('<gitlab-review-rb-bind-dn>', $ldapSearchUserDn).
    Replace('<gitlab-review-rb-pw>', $ldapSearchUserPassword).
    Replace('<gitlab-review-rb-base>', $config.shm.domain.ous.researchUsers.path).
    Replace('<gitlab-review-rb-user-filter>', "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.reviewUsers.name),$($config.shm.domain.securityOuPath)))").
    Replace('<gitlab-review-ip>', $config.sre.webapps.gitlabReview.ip).
    Replace('<gitlab-review-hostname>', $config.sre.webapps.gitlabReview.hostname).
    Replace('<gitlab-review-fqdn>', "$($config.sre.webapps.gitlabReview.hostname).$($config.sre.domain.fqdn)").
    Replace('<gitlab-review-root-password>', $gitlabReviewUserRootPassword).
    Replace('<gitlab-review-login-domain>', $config.shm.domain.fqdn).
    Replace('<gitlab-review-username>', $gitlabReviewUserIngressUsername).
    Replace('<gitlab-review-password>', $gitlabReviewUserIngressPassword).
    Replace('<gitlab-review-api-token>', $gitlabReviewAPIToken)
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
    $gitlabReviewCloudInit = $gitlabReviewCloudInit.Replace("${indent}<$scriptName>", $indented_script)
}
# Set GitLab review deployment parameters
$gitlabReviewDeploymentParams = @{
    AdminPassword = $gitlabReviewAdminPassword
    CloudInitYaml = $gitlabReviewCloudInit
    Name = $config.sre.webapps.gitlabReview.vmName
    PrivateIpAddress = $config.sre.webapps.gitlabReview.ip
    Size = $config.sre.webapps.gitlabReview.vmSize
    Subnet = $subnetAirlock
}
# Deploy GitLab review VM
try {
    Add-LogMessage -Level Warning "Temporarily allowing outbound internet access from $($config.sre.webapps.gitlabReview.ip)..."
    Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgAirlock -Name "TmpAllowOutboundInternetGitlabReview" -SourceAddressPrefix $config.sre.webapps.gitlabReview.ip -Access Allow -Description "Allow outbound internet" -DestinationAddressPrefix Internet -DestinationPortRange * -Direction Outbound -Priority 100 -Protocol * -SourcePortRange *
    $null = Deploy-UbuntuVirtualMachine @gitlabReviewDeploymentParams @commonDeploymentParams
    Enable-AzVM -Name $config.sre.webapps.gitlabReview.vmName -ResourceGroupName $config.sre.webapps.rg
} finally {
    $null = Remove-AzNetworkSecurityRuleConfig -Name "TmpAllowOutboundInternetGitlabReview" -NetworkSecurityGroup $nsgAirlock
}


# List VMs connected to each NSG
# ------------------------------
foreach ($nsg in @($nsgWebapps, $nsgAirlock)) {
    Add-LogMessage -Level Info "Summary: NICs associated with '$($nsg.Name)' NSG"
    @($nsg.NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
