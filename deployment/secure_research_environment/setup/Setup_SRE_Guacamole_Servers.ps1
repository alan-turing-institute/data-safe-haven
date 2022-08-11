param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Applications -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureDns -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Cryptography -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Check that we are using the correct provider
# --------------------------------------------
if ($config.sre.remoteDesktop.provider -ne "ApacheGuacamole") {
    Add-LogMessage -Level Fatal "You should not be running this script when using remote desktop provider '$($config.sre.remoteDesktop.provider)'"
}


# Retrieve VNET and subnets
# -------------------------
Add-LogMessage -Level Info "Retrieving virtual network '$($config.sre.network.vnet.name)'..."
$vnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$guacamoleSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.remoteDesktop.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg
$deploymentSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.deployment.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg


# Get deployment IP address
# -------------------------
$deploymentIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet


# Create remote desktop resource group if it does not exist
# ---------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.remoteDesktop.rg -Location $config.sre.location


# Deploy a network card with a public IP address
# ----------------------------------------------
$networkCard = Deploy-NetworkInterface -Name "$($config.sre.remoteDesktop.guacamole.vmName)-NIC" -ResourceGroupName $config.sre.remoteDesktop.rg -Subnet $deploymentSubnet -PrivateIpAddress $deploymentIpAddress -Location $config.sre.location
$publicIp = Deploy-PublicIpAddress -Name "$($config.sre.remoteDesktop.guacamole.vmName)-PIP" -ResourceGroupName $config.sre.remoteDesktop.rg -AllocationMethod Static -Location $config.sre.location
$null = $networkCard | Set-AzNetworkInterfaceIpConfig -Name $networkCard.ipConfigurations[0].Name -SubnetId $deploymentSubnet.Id -PublicIpAddressId $publicIp.Id | Set-AzNetworkInterface


# Register AzureAD application
# ----------------------------
$azureAdApplicationName = "Guacamole SRE $($config.sre.id)"
Add-LogMessage -Level Info "Ensuring that '$azureAdApplicationName' is registered with Azure Active Directory..."
if (Get-MgContext) {
    Add-LogMessage -Level Info "Already authenticated against Microsoft Graph"
} else {
    Connect-MgGraph -TenantId $tenantId -Scopes "Application.ReadWrite.All", "Policy.ReadWrite.ApplicationConfiguration" -ErrorAction Stop
}
try {
    $application = Get-MgApplication -Filter "DisplayName eq '$azureAdApplicationName'"
    if (-not $application) {
        Add-LogMessage -Level Info "Registering '$azureAdApplicationName' with Azure Active Directory..."
        $application = New-MgApplication -DisplayName "$azureAdApplicationName" -SignInAudience "AzureADMyOrg" -Web @{ RedirectUris = @("https://$($config.sre.domain.fqdn)"); ImplicitGrantSettings = @{ EnableIdTokenIssuance = $true } }
    }
    if (Get-MgApplication -Filter "DisplayName eq '$azureAdApplicationName'") {
        Add-LogMessage -Level Success "'$azureAdApplicationName' is already registered in Azure Active Directory"
    } else {
        Add-LogMessage -Level Fatal "Failed to register '$azureAdApplicationName' in Azure Active Directory!"
    }
} catch {
    Add-LogMessage -Level Fatal "Could not connect to Microsoft Graph!" -Exception $_.Exception
}


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.remoteDesktop.guacamole.adminPasswordSecretName -DefaultLength 20
$guacamoleDbPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.remoteDesktop.guacamole.databaseAdminPasswordSecretName -DefaultLength 20 -AsPlaintext
$ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext


# Construct the cloud-init yaml file
# ----------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
$cloudInitTemplate = (Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-guacamole.mustache.yaml") | Get-Item | Get-Content -Raw
$cloudInitTemplate = Expand-CloudInitResources -Template $cloudInitTemplate -ResourcePath (Join-Path $PSScriptRoot ".." "cloud_init" "resources")
# Expand mustache template variables
$config["guacamole"] = @{
    applicationId          = $application.AppId
    disableCopy            = ($config.sre.remoteDesktop.networkRules.copyAllowed ? 'false' : 'true')
    disablePaste           = ($config.sre.remoteDesktop.networkRules.pasteAllowed ? 'false' : 'true')
    internalDbPassword     = $guacamoleDbPassword
    ipAddressFirstSRD      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset 160
    ldapGroupFilter        = "(&(objectClass=group)(CN=SG $($config.sre.domain.netbiosName)*))"
    ldapSearchUserDn       = "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)"
    ldapSearchUserPassword = $ldapSearchPassword
    ldapUserFilter         = "(&(objectClass=user)(|(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path))(memberOf=CN=$($config.shm.domain.securityGroups.serverAdmins.name),$($config.shm.domain.ous.securityGroups.path))))"
    sslCiphers             = (Get-SslCipherSuites)["openssl"] | Join-String -Separator ":"
    tenantId               = $tenantId
}
$cloudInitYaml = Expand-MustacheTemplate -Template $cloudInitTemplate -Parameters $config


# Deploy the VM
# -------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$params = @{
    AdminPassword          = $vmAdminPassword
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitYaml
    ImageSku               = "Ubuntu-latest"
    Location               = $config.sre.location
    Name                   = $config.sre.remoteDesktop.guacamole.vmName
    NicId                  = $networkCard.Id
    OsDiskSizeGb           = $config.sre.remoteDesktop.guacamole.disks.os.sizeGb
    OsDiskType             = $config.sre.remoteDesktop.guacamole.disks.os.type
    ResourceGroupName      = $config.sre.remoteDesktop.rg
    Size                   = $config.sre.remoteDesktop.guacamole.vmSize
}
$null = Deploy-LinuxVirtualMachine @params


# Change subnets and IP address while the VM is off then restart
# --------------------------------------------------------------
Update-VMIpAddress -Name $config.sre.remoteDesktop.guacamole.vmName -ResourceGroupName $config.sre.remoteDesktop.rg -Subnet $guacamoleSubnet -IpAddress $config.sre.remoteDesktop.guacamole.ip
Start-VM -Name $config.sre.remoteDesktop.guacamole.vmName -ResourceGroupName $config.sre.remoteDesktop.rg


# Add DNS records for Guacamole server
# ------------------------------------
Deploy-DnsRecordCollection -PublicIpAddress $publicIp.IpAddress `
                           -RecordNameA "@" `
                           -RecordNameCAA "letsencrypt.org" `
                           -RecordNameCName $serverHostname `
                           -ResourceGroupName $config.shm.dns.rg `
                           -SubscriptionName $config.shm.dns.subscriptionName `
                           -TtlSeconds 30 `
                           -ZoneName $config.sre.domain.fqdn


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
