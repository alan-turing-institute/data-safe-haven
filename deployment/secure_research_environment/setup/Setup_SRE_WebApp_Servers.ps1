param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
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
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$ldapSearchUserDn = "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)"


# Deploy and configure CodiMD VM
# ------------------------------
Add-LogMessage -Level Info "Constructing CodiMD cloud-init from template..."
$codimdCloudInitTemplate = Get-Content (Join-Path $cloudInitBasePath "cloud-init-codimd.template.yaml") -Raw
# Expand placeholders in the cloud-init template
$codimdCloudInitTemplate = $codimdCloudInitTemplate.
    Replace("<codimd-bind-creds>", $ldapSearchUserPassword).
    Replace("<codimd-bind-dn>", $ldapSearchUserDn).
    Replace("<codimd-fqdn>", "$($config.sre.webapps.codimd.hostname).$($config.sre.domain.fqdn)").
    Replace("<codimd-hostname>", $config.sre.webapps.codimd.hostname).
    Replace("<codimd-ip>", $config.sre.webapps.codimd.ip).
    Replace("<codimd-ldap-base>", $config.shm.domain.ous.researchUsers.path).
    Replace("<codimd-ldap-netbios>", $config.shm.domain.netbiosName).
    Replace("<codimd-ldap-url>", "ldap://$($config.shm.dc.fqdn)").
    Replace("<codimd-postgres-password>", $(Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.codimd.postgres.passwordSecretName -DefaultLength 20 -AsPlaintext)).
    Replace("<codimd-user-filter>", "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path))(sAMAccountName={{username}}))").
    Replace("<docker-codimd-version>", $config.sre.webapps.codimd.codimd.dockerVersion).
    Replace("<docker-postgres-version>", $config.sre.webapps.codimd.postgres.dockerVersion).
    Replace("<ntp-server>", $config.shm.time.ntp.poolFqdn).
    Replace("<timezone>", $config.sre.time.timezone.linux)
# Deploy CodiMD VM
$codimdDataDisk = Deploy-ManagedDisk -Name "$($config.sre.webapps.codimd.vmName)-DATA-DISK" -SizeGB $config.sre.webapps.codimd.disks.data.sizeGb -Type $config.sre.webapps.codimd.disks.data.type -ResourceGroupName $config.sre.webapps.rg -Location $config.sre.location
$params = @{
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.codimd.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $codimdCloudInitTemplate
    DataDiskIds            = @($codimdDataDisk.Id)
    ImageSku               = $config.sre.webapps.codimd.osVersion
    Location               = $config.sre.location
    Name                   = $config.sre.webapps.codimd.vmName
    OsDiskSizeGb           = $config.sre.webapps.codimd.disks.os.sizeGb
    OsDiskType             = $config.sre.webapps.codimd.disks.os.type
    PrivateIpAddress       = (Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet)
    ResourceGroupName      = $config.sre.webapps.rg
    Size                   = $config.sre.webapps.codimd.vmSize
    Subnet                 = $deploymentSubnet
}
$codimdVm = Deploy-UbuntuVirtualMachine @params
# Change subnets and IP address while CodiMD VM is off then restart
Update-VMIpAddress -Name $codimdVm.Name -ResourceGroupName $codimdVm.ResourceGroupName -Subnet $webappsSubnet -IpAddress $config.sre.webapps.codimd.ip


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
    Replace("<gitlab-root-password>", $(Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.rootPasswordSecretName -DefaultLength 20 -AsPlaintext)).
    Replace("<gitlab-login-domain>", $config.shm.domain.fqdn).
    Replace("<ntp-server>", $config.shm.time.ntp.poolFqdn).
    Replace("<timezone>", $config.sre.time.timezone.linux)
# Deploy GitLab VM
$gitlabDataDisk = Deploy-ManagedDisk -Name "$($config.sre.webapps.gitlab.vmName)-DATA-DISK" -SizeGB $config.sre.webapps.gitlab.disks.data.sizeGb -Type $config.sre.webapps.gitlab.disks.data.type -ResourceGroupName $config.sre.webapps.rg -Location $config.sre.location
$params = @{
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $gitlabCloudInitTemplate
    DataDiskIds            = @($gitlabDataDisk.Id)
    ImageSku               = $config.sre.webapps.gitlab.osVersion
    Location               = $config.sre.location
    Name                   = $config.sre.webapps.gitlab.vmName
    OsDiskSizeGb           = $config.sre.webapps.gitlab.disks.os.sizeGb
    OsDiskType             = $config.sre.webapps.gitlab.disks.os.type
    PrivateIpAddress       = (Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet)
    ResourceGroupName      = $config.sre.webapps.rg
    Size                   = $config.sre.webapps.gitlab.vmSize
    Subnet                 = $deploymentSubnet
}
$gitlabVm = Deploy-UbuntuVirtualMachine @params
# Change subnets and IP address while GitLab VM is off then restart
Update-VMIpAddress -Name $gitlabVm.Name -ResourceGroupName $gitlabVm.ResourceGroupName -Subnet $webappsSubnet -IpAddress $config.sre.webapps.gitlab.ip


# Deploy and configure CoCalc VM
# -------------------------------
Add-LogMessage -Level Info "Constructing CoCalc cloud-init from template..."
$cocalcCloudInitTemplate = Join-Path $cloudInitBasePath "cloud-init-cocalc.template.yaml" | Get-Item | Get-Content -Raw
# Insert resources into the cloud-init template
foreach ($resource in (Get-ChildItem (Join-Path $cloudInitBasePath "resources"))) {
    $indent = $cocalcCloudInitTemplate -split "`n" | Where-Object { $_ -match "{{$($resource.Name)}}" } | ForEach-Object { $_.Split("{")[0] } | Select-Object -First 1
    $indentedContent = (Get-Content $resource.FullName -Raw) -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $cocalcCloudInitTemplate = $cocalcCloudInitTemplate.Replace("${indent}{{$($resource.Name)}}", $indentedContent)
}
# Expand placeholders in the cloud-init template
$cocalcCloudInitTemplate = $cocalcCloudInitTemplate.
    Replace("{{cocalc-fqdn}}", "$($config.sre.webapps.cocalc.hostname).$($config.sre.domain.fqdn)").
    Replace("{{docker-codimd-version}}", $config.sre.webapps.cocalc.dockerVersion).
    Replace("{{mirror-index-pypi}}", $config.sre.repositories.pypi.index).
    Replace("{{mirror-index-url-pypi}}", $config.sre.repositories.pypi.indexUrl).
    Replace("{{mirror-host-pypi}}", $config.sre.repositories.pypi.host).
    Replace("{{mirror-url-cran}}", $config.sre.repositories.cran.url).
    Replace("{{ntp-server}}", $config.shm.time.ntp.poolFqdn).
    Replace("{{timezone}}", $config.sre.time.timezone.linux)
# Deploy CoCalc VM
$cocalcDataDisk = Deploy-ManagedDisk -Name "$($config.sre.webapps.cocalc.vmName)-DATA-DISK" -SizeGB $config.sre.webapps.cocalc.disks.data.sizeGb -Type $config.sre.webapps.cocalc.disks.data.type -ResourceGroupName $config.sre.webapps.rg -Location $config.sre.location
$params = @{
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.cocalc.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cocalcCloudInitTemplate
    DataDiskIds            = @($cocalcDataDisk.Id)
    ImageSku               = $config.sre.webapps.cocalc.osVersion
    Location               = $config.sre.location
    Name                   = $config.sre.webapps.cocalc.vmName
    OsDiskSizeGb           = $config.sre.webapps.cocalc.disks.os.sizeGb
    OsDiskType             = $config.sre.webapps.cocalc.disks.os.type
    PrivateIpAddress       = (Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet)
    ResourceGroupName      = $config.sre.webapps.rg
    Size                   = $config.sre.webapps.cocalc.vmSize
    Subnet                 = $deploymentSubnet
}
$cocalcVm = Deploy-UbuntuVirtualMachine @params
# Change subnets and IP address while CoCalc VM is off then restart
Update-VMIpAddress -Name $cocalcVm.Name -ResourceGroupName $cocalcVm.ResourceGroupName -Subnet $webappsSubnet -IpAddress $config.sre.webapps.cocalc.ip


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
