param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
$ldapSearchUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext
$config.sre.storage.persistentdata.ingressSasToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers.ingress.connectionSecretName -AsPlaintext


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


# Deploy and configure CoCalc VM
# -------------------------------
Add-LogMessage -Level Info "Constructing CoCalc cloud-init from template..."
# Load the cloud-init template then add resources and expand mustache placeholders
$cocalcCloudInitTemplate = Join-Path $cloudInitBasePath "cloud-init-cocalc.mustache.yaml" | Get-Item | Get-Content -Raw
$cocalcCloudInitTemplate = Expand-CloudInitResources -Template $cocalcCloudInitTemplate -ResourcePath (Join-Path $cloudInitBasePath "resources")
$cocalcCloudInitTemplate = Expand-MustacheTemplate -Template $cocalcCloudInitTemplate -Parameters $config
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
$cocalcVm = Deploy-LinuxVirtualMachine @params
# Change subnets and IP address while CoCalc VM is off then restart
Update-VMIpAddress -Name $cocalcVm.Name -ResourceGroupName $cocalcVm.ResourceGroupName -Subnet $webappsSubnet -IpAddress $config.sre.webapps.cocalc.ip
# Update DNS records for this VM
Update-VMDnsRecords -DcName $config.shm.dc.vmName -DcResourceGroupName $config.shm.dc.rg -BaseFqdn $config.sre.domain.fqdn -ShmSubscriptionName $config.shm.subscriptionName -VmHostname $config.sre.webapps.cocalc.hostname -VmIpAddress $config.sre.webapps.cocalc.ip


# Deploy and configure CodiMD VM
# ------------------------------
Add-LogMessage -Level Info "Constructing CodiMD cloud-init from template..."
# Load the cloud-init template and expand mustache placeholders
$config["codimd"] = @{
    ldapSearchUserDn       = $ldapSearchUserDn
    ldapSearchUserPassword = $ldapSearchUserPassword
    ldapUserFilter         = "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path))(sAMAccountName={{username}}))"
    postgresPassword       = $(Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.codimd.postgres.passwordSecretName -DefaultLength 20 -AsPlaintext)
}
$codimdCloudInitTemplate = Join-Path $cloudInitBasePath "cloud-init-codimd.mustache.yaml" | Get-Item | Get-Content -Raw
$codimdCloudInitTemplate = Expand-CloudInitResources -Template $codimdCloudInitTemplate -ResourcePath (Join-Path $cloudInitBasePath "resources")
$codimdCloudInitTemplate = Expand-MustacheTemplate -Template $codimdCloudInitTemplate -Parameters $config
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
$codimdVm = Deploy-LinuxVirtualMachine @params
# Change subnets and IP address while CodiMD VM is off then restart
Update-VMIpAddress -Name $codimdVm.Name -ResourceGroupName $codimdVm.ResourceGroupName -Subnet $webappsSubnet -IpAddress $config.sre.webapps.codimd.ip
# Update DNS records for this VM
Update-VMDnsRecords -DcName $config.shm.dc.vmName -DcResourceGroupName $config.shm.dc.rg -BaseFqdn $config.sre.domain.fqdn -ShmSubscriptionName $config.shm.subscriptionName -VmHostname $config.sre.webapps.codimd.hostname -VmIpAddress $config.sre.webapps.codimd.ip


# Deploy and configure GitLab VM
# ------------------------------
Add-LogMessage -Level Info "Constructing GitLab cloud-init from template..."
# Load the cloud-init template and expand mustache placeholders
$config["gitlab"] = @{
    ldapSearchUserDn       = $ldapSearchUserDn
    ldapSearchUserPassword = $ldapSearchUserPassword
    ldapUserFilter         = "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path)))"
    rootPassword           = $(Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.webapps.gitlab.rootPasswordSecretName -DefaultLength 20 -AsPlaintext)
}
$gitlabCloudInitTemplate = Join-Path $cloudInitBasePath "cloud-init-gitlab.mustache.yaml" | Get-Item | Get-Content -Raw
$gitlabCloudInitTemplate = Expand-CloudInitResources -Template $gitlabCloudInitTemplate -ResourcePath (Join-Path $cloudInitBasePath "resources")
$gitlabCloudInitTemplate = Expand-MustacheTemplate -Template $gitlabCloudInitTemplate -Parameters $config
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
$gitlabVm = Deploy-LinuxVirtualMachine @params
# Change subnets and IP address while GitLab VM is off then restart
Update-VMIpAddress -Name $gitlabVm.Name -ResourceGroupName $gitlabVm.ResourceGroupName -Subnet $webappsSubnet -IpAddress $config.sre.webapps.gitlab.ip
# Update DNS records for this VM
Update-VMDnsRecords -DcName $config.shm.dc.vmName -DcResourceGroupName $config.shm.dc.rg -BaseFqdn $config.sre.domain.fqdn -ShmSubscriptionName $config.shm.subscriptionName -VmHostname $config.sre.webapps.gitlab.hostname -VmIpAddress $config.sre.webapps.gitlab.ip


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
