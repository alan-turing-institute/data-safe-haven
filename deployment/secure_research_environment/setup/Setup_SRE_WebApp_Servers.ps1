param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$gitlabRootPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.rootPasswordSecretName -DefaultLength 20 -AsPlaintext
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext
$ldapSearchUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext


# Retrieve VNET and subnets
# -------------------------
Add-LogMessage -Level Info "Retrieving virtual network '$($config.sre.network.vnet.name)' and subnets..."
try {
    $vnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
    $deploymentSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.deployment.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
    $webappsSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.webapps.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
    Add-LogMessage -Level Success "Successfully retrieved virtual network '$($config.sre.network.vnet.name)' and subnets."
} catch {
    Add-LogMessage -Level Fatal "Failed to retrieve virtual network '$($config.sre.network.vnet.name)'!"
}


# Common components
# -----------------
$null = Deploy-ResourceGroup -Name $config.sre.webapps.rg -Location $config.sre.location
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$ldapSearchUserDn = "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)"


# Deploy and configure GitLab VM
# ------------------------------
Add-LogMessage -Level Info "Constructing GitLab cloud-init from template..."
$gitlabCloudInitTemplate = Get-Content (Join-Path $cloudInitBasePath "cloud-init-gitlab.template.yaml") -Raw
# Expand placeholders in the cloud-init template
$gitlabCloudInitTemplate = $gitlabCloudInitTemplate.
    Replace("<gitlab-rb-host>", "$($config.shm.dc.hostname).$($config.shm.domain.fqdn)").
    Replace("<gitlab-rb-bind-dn>", $ldapSearchUserDn).
    Replace("<gitlab-rb-pw>", $ldapSearchUserPassword).
    Replace("<gitlab-rb-base>", $config.shm.domain.ous.researchUsers.path).
    Replace("<gitlab-rb-user-filter>", "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path)))").
    Replace("<gitlab-ip>", $config.sre.webapps.gitlab.ip).
    Replace("<gitlab-hostname>", $config.sre.webapps.gitlab.hostname).
    Replace("<gitlab-fqdn>", "$($config.sre.webapps.gitlab.hostname).$($config.sre.domain.fqdn)").
    Replace("<gitlab-root-password>", $gitlabRootPassword).
    Replace("<gitlab-login-domain>", $config.shm.domain.fqdn).
    Replace("<ntp-server>", $config.shm.time.ntp.poolFqdn).
    Replace("<timezone>", $config.sre.time.timezone.linux)
# Deploy GitLab VM
$gitlabVmName = $config.sre.webapps.gitlab.vmName
$deploymentIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet
$networkCard = Deploy-VirtualMachineNIC -Name "${gitlabVmName}-NIC" -ResourceGroupName $config.sre.webapps.rg -Subnet $deploymentSubnet -PrivateIpAddress $deploymentIpAddress -Location $config.sre.location
$dataDisks = @(
    (Deploy-ManagedDisk -Name "${gitlabVmName}-DATA-DISK" -SizeGB $config.sre.webapps.gitlab.disks.data.sizeGb -Type $config.sre.webapps.gitlab.disks.data.type -ResourceGroupName $config.sre.webapps.rg -Location $config.sre.location)
)
$params = @{
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $gitlabCloudInitTemplate
    DataDiskIds            = ($dataDisks | ForEach-Object { $_.Id })
    ImageSku               = "18.04-LTS"
    Location               = $config.sre.location
    Name                   = $gitlabVmName
    NicId                  = $networkCard.Id
    OsDiskSizeGb           = $config.sre.webapps.gitlab.disks.os.sizeGb
    OsDiskType             = $config.sre.webapps.gitlab.disks.os.type
    ResourceGroupName      = $config.sre.webapps.rg
    Size                   = $config.sre.webapps.gitlab.vmSize
}
$null = Deploy-UbuntuVirtualMachine @params
# Change subnets and IP address while HackMD VM is off
Update-VMIpAddress -Name $gitlabVmName -ResourceGroupName $config.sre.webapps.rg -Subnet $webappsSubnet -IpAddress $config.sre.webapps.gitlab.ip
Start-VM -Name $gitlabVmName -ResourceGroupName $config.sre.webapps.rg -Force


# Deploy and configure HackMD VM
# ------------------------------
Add-LogMessage -Level Info "Constructing HackMD cloud-init from template..."
$hackmdCloudInitTemplate = Get-Content (Join-Path $cloudInitBasePath "cloud-init-hackmd.template.yaml") -Raw
# Expand placeholders in the cloud-init template
$hackmdCloudInitTemplate = $hackmdCloudInitTemplate.
    Replace("<hackmd-bind-dn>", $ldapSearchUserDn).
    Replace("<hackmd-bind-creds>", $ldapSearchUserPassword).
    Replace("<hackmd-user-filter>", "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path))(userPrincipalName={{username}}))").
    Replace("<hackmd-ldap-base>", $config.shm.domain.ous.researchUsers.path).
    Replace("<hackmd-ip>", $config.sre.webapps.hackmd.ip).
    Replace("<hackmd-hostname>", $config.sre.webapps.hackmd.hostname).
    Replace("<hackmd-fqdn>", "$($config.sre.webapps.hackmd.hostname).$($config.sre.domain.fqdn)").
    Replace("<hackmd-ldap-url>", "ldap://$($config.shm.dc.fqdn)").
    Replace("<hackmd-ldap-netbios>", $config.shm.domain.netbiosName).
    Replace("<ntp-server>", $config.shm.time.ntp.poolFqdn).
    Replace("<timezone>", $config.sre.time.timezone.linux)
# Deploy HackMD VM
$hackmdVmName = $config.sre.webapps.hackmd.vmName
$deploymentIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet
$networkCard = Deploy-VirtualMachineNIC -Name "${hackmdVmName}-NIC" -ResourceGroupName $config.sre.webapps.rg -Subnet $deploymentSubnet -PrivateIpAddress $deploymentIpAddress -Location $config.sre.location
$params = @{
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.hackmd.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $hackmdCloudInitTemplate
    ImageSku               = "18.04-LTS"
    Location               = $config.sre.location
    Name                   = $hackmdVmName
    NicId                  = $networkCard.Id
    OsDiskSizeGb           = $config.sre.webapps.hackmd.disks.os.sizeGb
    OsDiskType             = $config.sre.webapps.hackmd.disks.os.type
    ResourceGroupName      = $config.sre.webapps.rg
    Size                   = $config.sre.webapps.hackmd.vmSize
}
$null = Deploy-UbuntuVirtualMachine @params
# Change subnets and IP address while HackMD VM is off then restart
Update-VMIpAddress -Name $hackmdVmName -ResourceGroupName $config.sre.webapps.rg -Subnet $webappsSubnet -IpAddress $config.sre.webapps.hackmd.ip
Start-VM -Name $hackmdVmName -ResourceGroupName $config.sre.webapps.rg -Force


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
